import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
// stripe's CJS build uses `export =` (no esModuleInterop here) — import-equals form.
import Stripe = require('stripe');
import { StripeProvider } from './stripe.provider';

/**
 * The Stripe webhook authenticates by a timestamped HMAC over the RAW body
 * (Stripe-Signature header). A wrong secret, a tampered body, or a missing
 * signature must be rejected — otherwise a forged "payment approved" unlocks
 * paid features for free.
 *
 * Also pinned here: the port carries ONE instrument string, so Stripe's
 * (customer, payment_method) pair is encoded as `cus_xxx|pm_xxx` — composed by
 * parseWebhook, split by chargeStoredInstrument. That round-trip must hold.
 */
const SECRET = 'whsec_test';
const config = {
  get: (k: string) => (k === 'STRIPE_WEBHOOK_SECRET' ? SECRET : undefined),
} as unknown as ConfigService;

// Signing helper only — never talks to the network.
const stripeSigner = new Stripe('sk_test_signing_only');
const sign = (body: Buffer, secret = SECRET) =>
  stripeSigner.webhooks.generateTestHeaderString({ payload: body.toString('utf8'), secret });

const body = (over: Record<string, unknown> = {}) =>
  Buffer.from(
    JSON.stringify({
      id: 'evt_1',
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
          metadata: { userId: 'u1' },
        },
      },
      ...over,
    }),
  );

describe('StripeProvider.parseWebhook — signature verification', () => {
  const provider = new StripeProvider(config);

  it('accepts a correctly-signed event and maps its fields', () => {
    const raw = body();
    const event = provider.parseWebhook(raw, sign(raw));
    expect(event).toMatchObject({
      id: 'evt_1',
      type: 'payment_approved',
      providerPaymentId: 'pi_1',
      amountMinor: 19900,
      currency: 'USD',
      metadata: { userId: 'u1' },
    });
  });

  it('REJECTS a forged signature (wrong secret)', () => {
    const raw = body();
    expect(() => provider.parseWebhook(raw, sign(raw, 'whsec_wrong'))).toThrow(UnauthorizedException);
  });

  it('REJECTS a tampered body even with a signature valid for the original', () => {
    const original = body({ data: { object: { object: 'checkout.session', payment_status: 'paid', amount_total: 100 } } });
    const signature = sign(original);
    const tampered = body({ data: { object: { object: 'checkout.session', payment_status: 'paid', amount_total: 9_999_900 } } });
    expect(() => provider.parseWebhook(tampered, signature)).toThrow(UnauthorizedException);
  });

  it('REJECTS a missing signature', () => {
    expect(() => provider.parseWebhook(body(), '')).toThrow(UnauthorizedException);
  });

  it('400s when no webhook secret is configured — never trusts the payload', () => {
    const bare = new StripeProvider({ get: () => undefined } as unknown as ConfigService);
    expect(() => bare.parseWebhook(body(), 'anything')).toThrow(BadRequestException);
  });
});

describe('StripeProvider.parseWebhook — event mapping', () => {
  const provider = new StripeProvider(config);
  const parse = (raw: Buffer) => provider.parseWebhook(raw, sign(raw));

  it('checkout.session.completed that is NOT paid maps to "unknown", not an approval', () => {
    const raw = body({
      data: { object: { object: 'checkout.session', id: 'cs_1', payment_status: 'unpaid', metadata: { userId: 'u1' } } },
    });
    expect(parse(raw).type).toBe('unknown');
  });

  it('payment_intent.succeeded maps to approval and COMPOSES the cus|pm instrument', () => {
    const raw = body({
      id: 'evt_pi',
      type: 'payment_intent.succeeded',
      data: {
        object: {
          object: 'payment_intent',
          id: 'pi_1',
          amount: 19900,
          currency: 'usd',
          customer: 'cus_1',
          payment_method: 'pm_1',
          metadata: { userId: 'u1' },
        },
      },
    });
    expect(parse(raw)).toMatchObject({
      id: 'evt_pi',
      type: 'payment_approved',
      providerPaymentId: 'pi_1',
      amountMinor: 19900,
      currency: 'USD',
      paymentInstrumentId: 'cus_1|pm_1',
      metadata: { userId: 'u1' },
    });
  });

  it('payment_intent.succeeded WITHOUT a customer carries no instrument (one-off card)', () => {
    const raw = body({
      id: 'evt_pi2',
      type: 'payment_intent.succeeded',
      data: {
        object: { object: 'payment_intent', id: 'pi_2', amount: 100, currency: 'usd', payment_method: 'pm_1', metadata: {} },
      },
    });
    expect(parse(raw).paymentInstrumentId).toBeUndefined();
  });

  it('payment_intent.payment_failed maps to a decline', () => {
    const raw = body({
      id: 'evt_fail',
      type: 'payment_intent.payment_failed',
      data: {
        object: {
          object: 'payment_intent',
          id: 'pi_1',
          amount: 19900,
          currency: 'usd',
          last_payment_error: { message: 'Your card was declined.' },
          metadata: { userId: 'u1' },
        },
      },
    });
    expect(parse(raw)).toMatchObject({
      type: 'payment_declined',
      providerPaymentId: 'pi_1',
      metadata: { userId: 'u1' },
    });
  });

  it('charge.refunded maps to a refund with the refunded amount', () => {
    const raw = body({
      id: 'evt_refund',
      type: 'charge.refunded',
      data: {
        object: {
          object: 'charge',
          id: 'ch_1',
          payment_intent: 'pi_1',
          amount_refunded: 5000,
          currency: 'usd',
          metadata: { userId: 'u1' },
        },
      },
    });
    expect(parse(raw)).toMatchObject({
      type: 'payment_refunded',
      providerPaymentId: 'pi_1',
      amountMinor: 5000,
      currency: 'USD',
    });
  });

  it('maps an unrecognised event type to "unknown" rather than mis-handling it', () => {
    const raw = body({ type: 'customer.created', data: { object: { object: 'customer', id: 'cus_1' } } });
    expect(parse(raw).type).toBe('unknown');
  });
});

describe('StripeProvider.chargeStoredInstrument — cus|pm composite round-trip', () => {
  const chargeReq = {
    userId: 'u1',
    amountMinor: 19900,
    currency: 'USD',
    description: 'Wasiati Standard renewal',
    metadata: { userId: 'u1', subscriptionId: 's1' },
  };

  function providerWithMockedSdk(create: jest.Mock) {
    const provider = new StripeProvider(config);
    (provider as any).sdk = { paymentIntents: { create } };
    return provider;
  }

  it('splits the instrument parseWebhook composed and charges off-session', async () => {
    // Round-trip: the instrument string produced by the webhook mapping...
    const provider = providerWithMockedSdk(jest.fn(async () => ({ id: 'pi_new', status: 'succeeded' })));
    const raw = body({
      id: 'evt_pi',
      type: 'payment_intent.succeeded',
      data: {
        object: { object: 'payment_intent', id: 'pi_1', amount: 1, currency: 'usd', customer: 'cus_9', payment_method: 'pm_9', metadata: {} },
      },
    });
    const instrument = provider.parseWebhook(raw, sign(raw)).paymentInstrumentId!;
    expect(instrument).toBe('cus_9|pm_9');

    // ...is split back into the exact (customer, payment_method) pair.
    const result = await provider.chargeStoredInstrument({ ...chargeReq, paymentInstrumentId: instrument });
    expect(result).toEqual({ approved: true, providerPaymentId: 'pi_new' });
    const create = (provider as any).sdk.paymentIntents.create as jest.Mock;
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        customer: 'cus_9',
        payment_method: 'pm_9',
        amount: 19900,
        currency: 'usd',
        off_session: true,
        confirm: true,
        metadata: chargeReq.metadata,
      }),
    );
  });

  it('maps a card decline to approved:false with the decline reason', async () => {
    const provider = providerWithMockedSdk(
      jest.fn(async () => {
        throw Object.assign(new Error('Your card was declined.'), {
          type: 'StripeCardError',
          payment_intent: { id: 'pi_declined' },
        });
      }),
    );
    const result = await provider.chargeStoredInstrument({ ...chargeReq, paymentInstrumentId: 'cus_1|pm_1' });
    expect(result).toEqual({
      approved: false,
      providerPaymentId: 'pi_declined',
      declineReason: 'Your card was declined.',
    });
  });

  it('declines (never throws) on an instrument without the cus|pm shape', async () => {
    const create = jest.fn();
    const provider = providerWithMockedSdk(create);
    const result = await provider.chargeStoredInstrument({ ...chargeReq, paymentInstrumentId: 'src_legacy' });
    expect(result.approved).toBe(false);
    expect(result.declineReason).toMatch(/instrument/i);
    expect(create).not.toHaveBeenCalled();
  });

  it('degrades gracefully with NO keys configured: declines instead of crashing', async () => {
    const provider = new StripeProvider({ get: () => undefined } as unknown as ConfigService);
    const result = await provider.chargeStoredInstrument({ ...chargeReq, paymentInstrumentId: 'cus_1|pm_1' });
    expect(result.approved).toBe(false);
    expect(result.declineReason).toMatch(/not configured/i);
  });
});

describe('StripeProvider — unconfigured environment', () => {
  it('createHostedPayment fails with a clean 400 when no secret key is set', async () => {
    const provider = new StripeProvider({ get: () => undefined } as unknown as ConfigService);
    await expect(
      provider.createHostedPayment({
        userId: 'u1',
        email: 'a@b.com',
        amountMinor: 19900,
        currency: 'USD',
        description: 'Wasiati Basic (one-time)',
        successUrl: 'https://app.wasiati.com/s',
        cancelUrl: 'https://app.wasiati.com/c',
        storeInstrument: false,
        metadata: {},
      }),
    ).rejects.toThrow(BadRequestException);
  });
});
