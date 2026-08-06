import { Prisma, Region, SubscriptionTier } from '@prisma/client';
// stripe's CJS build uses `export =` (no esModuleInterop here) — import-equals form.
import Stripe = require('stripe');
import { PaymentsService } from './payments.service';
import { StripeProvider } from './providers/stripe.provider';

/**
 * Account credit is CONSUMED when checkout is created (the hosted page needs a
 * final amount) — so every way a session can end without money arriving must
 * give it back, and give it back EXACTLY ONCE. The trap this pins: an abandoned
 * session fires `checkout.session.expired`, which used to fall through to
 * `unknown` — a customer who opened checkout and closed the tab silently lost
 * real balance.
 *
 * "Exactly once" holds across:
 *   · a REPLAYED webhook (same event id)      → ProcessedPaymentEvent claim
 *   · decline then expiry of the SAME attempt → credit-ledger unique key on the
 *     attemptId (two DISTINCT event ids, so the claim alone would pass both)
 *
 * Payloads are genuinely signed; parsing runs through the real StripeProvider
 * and the real decline/expiry handlers — nothing in the path is stubbed.
 */
const WEBHOOK_SECRET = 'whsec_test';
const stripeSigner = new Stripe('sk_test_signing_only');

function signedEvent(event: Record<string, unknown>) {
  const payload = JSON.stringify(event);
  return {
    raw: Buffer.from(payload),
    signature: stripeSigner.webhooks.generateTestHeaderString({ payload, secret: WEBHOOK_SECRET }),
  };
}

/** Mirrors CreditsService.grant against @@unique([sourceType, sourceId, userId]). */
function creditLedger() {
  const grants: any[] = [];
  const keys = new Set<string>();
  return {
    grants,
    grant: async (p: any) => {
      const key = `${p.sourceType}|${p.sourceId}|${p.userId}`;
      if (p.sourceType && p.sourceId && keys.has(key)) return { granted: false };
      keys.add(key);
      grants.push(p);
      return { granted: true };
    },
  };
}

function makeService() {
  const config: any = { get: (k: string) => (k === 'STRIPE_WEBHOOK_SECRET' ? WEBHOOK_SECRET : undefined) };
  const provider = new StripeProvider(config);
  const seen = new Set<string>();
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
        seen.delete(where.id);
        return {};
      },
    },
  };
  const credits = creditLedger();
  const svc = new PaymentsService(
    config,
    prisma,
    {} as any, // notifications
    credits as any,
    {} as any, // referrals
    {} as any, // promotions
    {} as any, // invoices
    provider,
  );
  return { svc, credits };
}

/** The metadata a real checkout stamps on the session (see createCheckoutSession). */
const checkoutMetadata = (attemptId: string, creditMinor: number) => ({
  userId: 'u1',
  tier: 'STANDARD',
  interval: 'YEAR',
  planId: 'plan_std_year',
  attemptId,
  creditAppliedMinor: String(creditMinor),
  creditCurrency: 'USD',
  basisMinor: '9900',
  basisCurrency: 'USD',
});

const expiredSession = (eventId: string, metadata: Record<string, string>) => ({
  id: eventId,
  object: 'event',
  type: 'checkout.session.expired',
  data: {
    object: {
      object: 'checkout.session',
      id: 'cs_1',
      payment_status: 'unpaid',
      metadata,
    },
  },
});

const declinedIntent = (eventId: string, metadata: Record<string, string>) => ({
  id: eventId,
  object: 'event',
  type: 'payment_intent.payment_failed',
  data: {
    object: {
      object: 'payment_intent',
      id: 'pi_1',
      amount: 9400,
      currency: 'usd',
      last_payment_error: { message: 'Your card was declined.' },
      metadata,
    },
  },
});

describe('an abandoned checkout returns the consumed credit', () => {
  it('checkout.session.expired gives the credit back, keyed on the ATTEMPT', async () => {
    const { svc, credits } = makeService();
    const { raw, signature } = signedEvent(expiredSession('evt_exp_1', checkoutMetadata('plan_std_year:111', 500)));

    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(credits.grants).toHaveLength(1);
    expect(credits.grants[0]).toMatchObject({
      userId: 'u1',
      amountMinor: 500,
      currency: 'USD',
      sourceId: 'plan_std_year:111', // per-attempt, not per-plan or per-user
    });
  });

  it('a REPLAYED expiry webhook (same event id) does not refund twice', async () => {
    const { svc, credits } = makeService();
    const { raw, signature } = signedEvent(expiredSession('evt_exp_1', checkoutMetadata('plan_std_year:111', 500)));

    await svc.handleWebhook(raw, signature);
    // Stripe redelivers the identical event — the claim-first guard eats it.
    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true, duplicate: true });
    expect(credits.grants).toHaveLength(1);
  });

  it('a decline then the SAME session expiring returns the credit ONCE (distinct event ids)', async () => {
    const { svc, credits } = makeService();
    const metadata = checkoutMetadata('plan_std_year:222', 700);

    const decline = signedEvent(declinedIntent('evt_dec_1', metadata));
    await svc.handleWebhook(decline.raw, decline.signature);

    // The customer walks away; 24h later Stripe expires the very same session.
    const expiry = signedEvent(expiredSession('evt_exp_2', metadata));
    await svc.handleWebhook(expiry.raw, expiry.signature);

    // Two events, two distinct ids — but ONE attempt, so one return.
    expect(credits.grants).toHaveLength(1);
    expect(credits.grants[0]).toMatchObject({ amountMinor: 700, sourceId: 'plan_std_year:222' });
  });

  it('two DIFFERENT attempts at the same plan each get their own credit back', async () => {
    // Per-plan keying (the old decline behaviour) would swallow the second one.
    const { svc, credits } = makeService();

    const first = signedEvent(expiredSession('evt_exp_a', checkoutMetadata('plan_std_year:333', 400)));
    await svc.handleWebhook(first.raw, first.signature);
    const second = signedEvent(expiredSession('evt_exp_b', checkoutMetadata('plan_std_year:444', 400)));
    await svc.handleWebhook(second.raw, second.signature);

    expect(credits.grants).toHaveLength(2);
  });

  it('an expired session that consumed NO credit grants nothing', async () => {
    const { svc, credits } = makeService();
    const { raw, signature } = signedEvent(expiredSession('evt_exp_0', checkoutMetadata('plan_std_year:555', 0)));

    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(credits.grants).toHaveLength(0);
  });

  it('a declined RENEWAL does not return credit here — the renewal job already did', async () => {
    // Renewal charge metadata carries subscriptionId (see SubscriptionsService.renew),
    // and renew() grants the credit back synchronously on decline. A second grant
    // from the webhook would pay the customer twice for one decline.
    const { svc, credits } = makeService();
    const { raw, signature } = signedEvent(
      declinedIntent('evt_dec_renewal', {
        userId: 'u1',
        subscriptionId: 's1',
        tier: 'STANDARD',
        interval: 'YEAR',
        creditAppliedMinor: '400',
        creditCurrency: 'USD',
      }),
    );

    expect(await svc.handleWebhook(raw, signature)).toEqual({ received: true });
    expect(credits.grants).toHaveLength(0);
  });
});

describe('checkout stamps the attemptId the refund path depends on', () => {
  it('the session metadata carries the SAME attemptId the credit was consumed under', async () => {
    const consumed: any[] = [];
    const hosted: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: {
        findMany: async () => [
          {
            id: 'plan_std_year',
            tier: SubscriptionTier.STANDARD,
            interval: 'YEAR',
            region: Region.US,
            displayName: 'Standard',
            unitAmount: 9900,
            currency: 'USD',
            active: true,
          },
        ],
      },
    };
    const svc = new PaymentsService(
      { get: () => undefined } as any,
      prisma,
      {} as any,
      {
        consume: async (p: any) => {
          consumed.push(p);
          return 500; // some credit applied — the case where expiry matters
        },
      } as any,
      { pendingDiscountPercent: async () => 0 } as any,
      {} as any,
      {} as any,
      {
        createHostedPayment: async (req: any) => {
          hosted.push(req);
          return { redirectUrl: 'https://pay.example/x', sessionId: 'cs_1' };
        },
      } as any,
    );

    await svc.createCheckoutSession({
      userId: 'u1',
      tier: SubscriptionTier.STANDARD,
      interval: 'YEAR' as any,
      successUrl: 'https://app.wasiati.com/s',
      cancelUrl: 'https://app.wasiati.com/c',
    });

    // Without this thread the expiry webhook cannot key the return to the ledger
    // row that consumed the credit — and the per-attempt dedupe collapses.
    expect(consumed).toHaveLength(1);
    expect(hosted).toHaveLength(1);
    expect(hosted[0].metadata.attemptId).toBe(consumed[0].sourceId);
    expect(hosted[0].metadata.creditAppliedMinor).toBe('500');
  });
});
