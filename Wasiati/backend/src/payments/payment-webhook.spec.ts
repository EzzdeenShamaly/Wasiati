import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
// stripe's CJS build uses `export =` (no esModuleInterop here) — import-equals form.
import Stripe = require('stripe');
import { PaymentsService } from './payments.service';
import { StripeProvider } from './providers/stripe.provider';

/**
 * Webhook handling through the REAL StripeProvider — every payload below is
 * genuinely signed (stripe.webhooks.generateTestHeaderString), so signature
 * verification is exercised, not stubbed. Pinned behavior:
 *   1. Webhook idempotency is CLAIM-FIRST — a replayed event id is a no-op, and a
 *      concurrent duplicate can't double-fire the referral/promo ledgers; a
 *      processing failure RELEASES the claim so Stripe's retry can reprocess.
 *   2. A forged signature is rejected BEFORE any claim is written.
 *   3. Checkout return URLs are constrained to PAYMENT_RETURN_HOSTS (open-redirect).
 */
const WEBHOOK_SECRET = 'whsec_test';

// Signing helper only — never talks to the network.
const stripeSigner = new Stripe('sk_test_signing_only');

/** A raw body + a Stripe-Signature header that is genuinely valid for it. */
function signedEvent(event: Record<string, unknown>, secret: string = WEBHOOK_SECRET) {
  const payload = JSON.stringify(event);
  return {
    raw: Buffer.from(payload),
    signature: stripeSigner.webhooks.generateTestHeaderString({ payload, secret }),
  };
}

function makeService(opts: {
  seen?: Set<string>;
  config?: Record<string, string>;
  onProcess?: () => void | Promise<void>;
  user?: any;
}) {
  const seen = opts.seen ?? new Set<string>();
  const deleted: string[] = [];
  const config: any = {
    get: (k: string) => (k === 'STRIPE_WEBHOOK_SECRET' ? WEBHOOK_SECRET : opts.config?.[k]),
  };
  const provider = new StripeProvider(config);
  const prisma: any = {
    processedPaymentEvent: {
      create: async ({ data }: any) => {
        if (seen.has(data.id)) {
          throw new Prisma.PrismaClientKnownRequestError('dup', { code: 'P2002', clientVersion: 't' });
        }
        seen.add(data.id);
        return data;
      },
      delete: async ({ where }: any) => {
        deleted.push(where.id);
        seen.delete(where.id);
        return {};
      },
    },
    user: { findUnique: async () => opts.user ?? { id: 'u1', email: 'a@b.com', region: 'US' } },
  };
  const svc = new PaymentsService(
    config,
    prisma,
    {} as any, // notifications
    {} as any, // credits
    {} as any, // referrals
    {} as any, // promotions
    {} as any, // invoices
    provider,
  );
  // Stub the side-effect handlers so we can drive success/failure deterministically
  // AND observe exactly what the parsed event handed them.
  const calls: { approved: any[]; declined: any[]; refunded: any[]; stored: any[] } = {
    approved: [],
    declined: [],
    refunded: [],
    stored: [],
  };
  // onPaymentApproved takes the whole normalised PaymentEvent — the invoice needs
  // the amount/currency the older (metadata, instrument, paymentId) signature dropped.
  (svc as any).onPaymentApproved = async (event: any) => {
    calls.approved.push({
      metadata: event.metadata,
      instrument: event.paymentInstrumentId,
      paymentId: event.providerPaymentId,
      amountMinor: event.amountMinor,
      currency: event.currency,
    });
    if (opts.onProcess) await opts.onProcess();
  };
  (svc as any).onPaymentDeclined = async (metadata: any) => {
    calls.declined.push({ metadata });
  };
  (svc as any).onPaymentRefunded = async (metadata: any, paymentId?: string) => {
    calls.refunded.push({ metadata, paymentId });
  };
  (svc as any).onInstrumentStored = async (metadata: any, instrument?: string) => {
    calls.stored.push({ metadata, instrument });
  };
  return { svc, seen, deleted, calls };
}

const approvedSession = (id = 'evt_1') => ({
  id,
  object: 'event',
  type: 'checkout.session.completed',
  data: {
    object: {
      object: 'checkout.session',
      id: 'cs_1',
      payment_status: 'paid',
      payment_intent: 'pi_1',
      amount_total: 19900,
      currency: 'usd',
      metadata: { userId: 'u1', tier: 'BASIC', interval: 'ONE_TIME' },
    },
  },
});

describe('PaymentsService.handleWebhook — Stripe events end to end', () => {
  it('processes a signed checkout.session.completed once, with the session metadata', async () => {
    const { svc, calls } = makeService({});
    const { raw, signature } = signedEvent(approvedSession());
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(calls.approved).toHaveLength(1);
    expect(calls.approved[0]).toMatchObject({
      metadata: { userId: 'u1', tier: 'BASIC', interval: 'ONE_TIME' },
      paymentId: 'pi_1',
    });
  });

  it('hands the STORED INSTRUMENT (cus|pm composite) through on payment_intent.succeeded', async () => {
    const { svc, calls } = makeService({});
    const { raw, signature } = signedEvent({
      id: 'evt_pi',
      object: 'event',
      type: 'payment_intent.succeeded',
      data: {
        object: {
          object: 'payment_intent',
          id: 'pi_1',
          amount: 19900,
          currency: 'usd',
          customer: 'cus_1',
          payment_method: 'pm_1',
          metadata: { userId: 'u1', tier: 'STANDARD', interval: 'YEAR' },
        },
      },
    });
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(calls.approved).toHaveLength(1);
    expect(calls.approved[0]).toMatchObject({
      metadata: { userId: 'u1', tier: 'STANDARD', interval: 'YEAR' },
      instrument: 'cus_1|pm_1',
      paymentId: 'pi_1',
    });
  });

  it('routes payment_intent.payment_failed to the DECLINE handler (credit return)', async () => {
    const { svc, calls } = makeService({});
    const { raw, signature } = signedEvent({
      id: 'evt_fail',
      object: 'event',
      type: 'payment_intent.payment_failed',
      data: {
        object: {
          object: 'payment_intent',
          id: 'pi_1',
          amount: 19900,
          currency: 'usd',
          last_payment_error: { message: 'Your card was declined.' },
          metadata: { userId: 'u1', creditAppliedMinor: '500', creditCurrency: 'USD' },
        },
      },
    });
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(calls.declined).toHaveLength(1);
    expect(calls.declined[0].metadata).toMatchObject({ userId: 'u1', creditAppliedMinor: '500' });
  });

  it('routes charge.refunded to the REFUND handler', async () => {
    const { svc, calls } = makeService({});
    const { raw, signature } = signedEvent({
      id: 'evt_refund',
      object: 'event',
      type: 'charge.refunded',
      data: {
        object: {
          object: 'charge',
          id: 'ch_1',
          payment_intent: 'pi_1',
          amount_refunded: 19900,
          currency: 'usd',
          metadata: { userId: 'u1' },
        },
      },
    });
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(calls.refunded).toHaveLength(1);
    expect(calls.refunded[0].metadata).toMatchObject({ userId: 'u1' });
  });

  it('routes setup_intent.succeeded to the CHANGE-CARD handler with the new instrument', async () => {
    // The "change card" flow completing. This event — not the setup-mode
    // checkout.session.completed — is the one carrying the payment_method.
    const { svc, calls } = makeService({});
    const { raw, signature } = signedEvent({
      id: 'evt_setup',
      object: 'event',
      type: 'setup_intent.succeeded',
      data: {
        object: {
          object: 'setup_intent',
          id: 'seti_1',
          customer: 'cus_1',
          payment_method: 'pm_new',
          metadata: { userId: 'u1', subscriptionId: 's1' },
        },
      },
    });
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(calls.stored).toHaveLength(1);
    expect(calls.stored[0]).toMatchObject({ metadata: { userId: 'u1' }, instrument: 'cus_1|pm_new' });
    // A card setup must never be mistaken for a payment.
    expect(calls.approved).toHaveLength(0);
  });

  it('REJECTS a forged signature before claiming anything', async () => {
    const { svc, seen, calls } = makeService({});
    const { raw, signature } = signedEvent(approvedSession(), 'whsec_wrong');
    await expect(svc.handleWebhook(raw, signature)).rejects.toThrow(UnauthorizedException);
    expect(seen.size).toBe(0); // no idempotency claim was written
    expect(calls.approved).toHaveLength(0);
  });
});

describe('PaymentsService.handleWebhook — idempotency (claim-first)', () => {
  it('IGNORES a replay of an already-processed event id', async () => {
    const seen = new Set<string>(['evt_1']); // already processed
    const { svc, calls } = makeService({ seen });
    const { raw, signature } = signedEvent(approvedSession());
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true, duplicate: true });
    expect(calls.approved).toHaveLength(0);
  });

  it('RELEASES the claim when processing fails, so the Stripe retry can reprocess', async () => {
    const { svc, seen, deleted } = makeService({
      onProcess: () => {
        throw new Error('downstream boom');
      },
    });
    const { raw, signature } = signedEvent(approvedSession());
    await expect(svc.handleWebhook(raw, signature)).rejects.toThrow('downstream boom');
    expect(deleted).toContain('evt_1'); // claim released
    expect(seen.has('evt_1')).toBe(false); // so a retry is not treated as a duplicate
  });
});

describe('PaymentsService.createCheckoutSession — open-redirect guard', () => {
  // No `region`: checkout reads it from the buyer's account (the prisma stub's user),
  // never from the caller.
  const base = {
    userId: 'u1',
    tier: 'BASIC' as const,
    successUrl: 'https://evil.example/success',
    cancelUrl: 'https://app.wasiati.com/cancel',
  };

  it('REJECTS a return URL not on PAYMENT_RETURN_HOSTS', async () => {
    const { svc } = makeService({ config: { PAYMENT_RETURN_HOSTS: 'app.wasiati.com' } });
    await expect(svc.createCheckoutSession(base as any)).rejects.toThrow(BadRequestException);
  });

  it('REJECTS a plain-http return URL when a host list is set', async () => {
    const { svc } = makeService({ config: { PAYMENT_RETURN_HOSTS: 'app.wasiati.com' } });
    await expect(
      svc.createCheckoutSession({ ...base, successUrl: 'http://app.wasiati.com/s' } as any),
    ).rejects.toThrow(BadRequestException);
  });

  it('is permissive when no host list is configured (dev)', async () => {
    // No PAYMENT_RETURN_HOSTS → the guard is a no-op; the call proceeds past it and
    // fails later on the missing plan lookup, NOT on the URL.
    const { svc } = makeService({ config: {} });
    await expect(svc.createCheckoutSession(base as any)).rejects.not.toThrow(/Return URL/i);
  });
});
