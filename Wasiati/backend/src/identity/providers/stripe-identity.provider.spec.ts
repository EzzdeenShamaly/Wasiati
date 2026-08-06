import { ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
// stripe's CJS build uses `export =` (no esModuleInterop here) — import-equals form.
import Stripe = require('stripe');
import { StripeIdentityProvider } from './stripe-identity.provider';
import { SumsubIdentityProvider } from './sumsub-identity.provider';
import { UnconfiguredIdentityProvider } from './unconfigured-identity.provider';
import { IdentityModule } from '../identity.module';
import { IDENTITY_PROVIDER, IdentityProviderPort } from '../identity-provider.interface';

/**
 * Stripe Identity is the decided US/CA KYC rail (docs/DECISIONS.md §13). Two things
 * are load-bearing and pinned here:
 *
 *  1. The webhook authenticates by a timestamped HMAC over the RAW body
 *     (Stripe-Signature). A forged, tampered or missing signature must THROW — a
 *     KYC status must never move on an unauthenticated payload, or anyone who can
 *     POST to /identity/webhook mints a "verified" identity on a will.
 *  2. The user is recovered from metadata WE stamped at session creation, never from
 *     anything a caller can put in the payload.
 *
 * The Stripe account is not live yet, so the SDK is mocked for session creation and
 * only the (offline, pure-HMAC) signing helper is real.
 */
const SECRET = 'whsec_test_pinned_signing_secret_0123456789';
const KEY = 'sk_test_pinned_identity_key_0123456789';

const configWith = (over: Record<string, string | undefined> = {}) =>
  ({
    get: (k: string) =>
      ({
        STRIPE_SECRET_KEY: KEY,
        STRIPE_WEBHOOK_SECRET: SECRET,
        APP_BASE_URL: 'https://app.wasiati.com',
        ...over,
      })[k],
  }) as unknown as ConfigService;

// Offline signing helper — pure HMAC, never talks to the network.
const stripeSigner = new Stripe('sk_test_signing_only');
const sign = (body: Buffer, secret = SECRET) =>
  stripeSigner.webhooks.generateTestHeaderString({ payload: body.toString('utf8'), secret });

const event = (type: string, session: Record<string, unknown> = {}) =>
  Buffer.from(
    JSON.stringify({
      id: 'evt_1',
      object: 'event',
      type,
      data: {
        object: {
          object: 'identity.verification_session',
          id: 'vs_1',
          status: 'verified',
          metadata: { wasiatiUserId: 'user-1' },
          ...session,
        },
      },
    }),
  );

/** A provider whose SDK call is stubbed — no live Stripe account exists yet. */
function providerWithMockedSdk(create: jest.Mock, config = configWith()) {
  const provider = new StripeIdentityProvider(config);
  (provider as any).sdk = { identity: { verificationSessions: { create } } };
  return provider;
}

describe('StripeIdentityProvider — configuration', () => {
  it('is configured only when BOTH the secret key and the webhook secret are present', () => {
    expect(new StripeIdentityProvider(configWith()).configured).toBe(true);
    // The outcome arrives ONLY by signed webhook: no signing secret means this
    // instance could never legitimately mark anyone VERIFIED.
    expect(new StripeIdentityProvider(configWith({ STRIPE_WEBHOOK_SECRET: undefined })).configured).toBe(false);
    expect(new StripeIdentityProvider(configWith({ STRIPE_SECRET_KEY: undefined })).configured).toBe(false);
  });

  it('treats a BLANK or PLACEHOLDER key as absent rather than crashing on it', () => {
    const cases = [
      { STRIPE_SECRET_KEY: '' },
      { STRIPE_SECRET_KEY: '   ' },
      { STRIPE_SECRET_KEY: 'sk_test_xxxxxxxxxxxxxxxx' },
      { STRIPE_SECRET_KEY: 'your_key_here' },
      { STRIPE_SECRET_KEY: '<set-me>' },
      { STRIPE_WEBHOOK_SECRET: '' },
      { STRIPE_WEBHOOK_SECRET: 'changeme-changeme-changeme' },
      // Right kind of secret, wrong slot: a publishable key is not a secret key.
      { STRIPE_SECRET_KEY: 'pk_test_0123456789abcdefghij' },
      // A signing secret must be a whsec_, not the API key pasted twice.
      { STRIPE_WEBHOOK_SECRET: KEY },
    ];
    for (const over of cases) {
      expect(new StripeIdentityProvider(configWith(over)).configured).toBe(false);
    }
  });

  it('refuses to start a session when unconfigured — never a silent pass', async () => {
    const svc = new StripeIdentityProvider(configWith({ STRIPE_SECRET_KEY: undefined }));
    await expect(svc.createSession({ userId: 'u1', email: 'a@b.com' })).rejects.toThrow(ServiceUnavailableException);
  });

  it('constructing the adapter with NO env at all does not throw — the app must still boot', () => {
    const bare = new StripeIdentityProvider({ get: () => undefined } as unknown as ConfigService);
    expect(bare.configured).toBe(false);
    expect(bare.name).toBe('STRIPE_IDENTITY');
  });
});

describe('StripeIdentityProvider.createSession', () => {
  const created = {
    id: 'vs_123',
    url: 'https://verify.stripe.com/start/vs_123_secret',
  };

  it('returns the hosted url + session id and STAMPS the user id into metadata', async () => {
    const create = jest.fn(async (_params: any) => created);
    const provider = providerWithMockedSdk(create);

    const session = await provider.createSession({ userId: 'user-1', email: 'a@b.com' });

    expect(session).toEqual({ url: created.url, sessionId: 'vs_123' });
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'document',
        metadata: { wasiatiUserId: 'user-1' },
        client_reference_id: 'user-1',
        provided_details: { email: 'a@b.com' },
      }),
    );
  });

  it('requires live capture and a matching selfie — the checks we do NOT build ourselves', async () => {
    const create = jest.fn(async (_params: any) => created);
    await providerWithMockedSdk(create).createSession({ userId: 'user-1', email: 'a@b.com' });

    expect(create.mock.calls[0][0]).toMatchObject({
      options: { document: { require_live_capture: true, require_matching_selfie: true } },
    });
  });

  it('sends the user back to the app afterwards, honouring an explicit override', async () => {
    const create = jest.fn(async (_params: any) => created);
    await providerWithMockedSdk(create).createSession({ userId: 'u1', email: 'a@b.com' });
    expect(create.mock.calls[0][0].return_url).toBe('https://app.wasiati.com/identity/verified');

    const create2 = jest.fn(async (_params: any) => created);
    await providerWithMockedSdk(
      create2,
      configWith({ STRIPE_IDENTITY_RETURN_URL: 'https://app.wasiati.com/kyc/done' }),
    ).createSession({ userId: 'u1', email: 'a@b.com' });
    expect(create2.mock.calls[0][0].return_url).toBe('https://app.wasiati.com/kyc/done');
  });

  it('surfaces a Stripe outage as a clean 503, not a 500', async () => {
    const provider = providerWithMockedSdk(
      jest.fn(async () => {
        throw new Error('connect ECONNREFUSED');
      }),
    );
    await expect(provider.createSession({ userId: 'u1', email: 'a@b.com' })).rejects.toThrow(
      ServiceUnavailableException,
    );
  });

  it('refuses a session Stripe returned without a hosted link', async () => {
    const provider = providerWithMockedSdk(jest.fn(async () => ({ id: 'vs_1', url: null })));
    await expect(provider.createSession({ userId: 'u1', email: 'a@b.com' })).rejects.toThrow(/verification link/i);
  });
});

describe('StripeIdentityProvider.parseWebhook — signature verification', () => {
  const provider = new StripeIdentityProvider(configWith());

  it('accepts a correctly-signed event', () => {
    const raw = event('identity.verification_session.verified');
    expect(provider.parseWebhook(raw, sign(raw))).toEqual({
      userId: 'user-1',
      status: 'VERIFIED',
      providerRef: 'vs_1',
    });
  });

  it('REJECTS a forged signature and returns NO outcome', () => {
    const raw = event('identity.verification_session.verified');
    const forged = sign(raw, 'whsec_not_the_real_signing_secret_0000');
    expect(() => provider.parseWebhook(raw, forged)).toThrow(UnauthorizedException);
  });

  it('REJECTS a tampered body even with a signature valid for the original', () => {
    const original = event('identity.verification_session.requires_input');
    const signature = sign(original);
    const tampered = event('identity.verification_session.verified');
    expect(() => provider.parseWebhook(tampered, signature)).toThrow(UnauthorizedException);
  });

  it('REJECTS a missing signature rather than trusting the payload', () => {
    const raw = event('identity.verification_session.verified');
    expect(() => provider.parseWebhook(raw, '')).toThrow(UnauthorizedException);
    expect(() => provider.parseWebhook(raw, undefined as unknown as string)).toThrow(UnauthorizedException);
  });

  it('REJECTS an unsigned payload that names another user (no privilege escalation)', () => {
    const raw = event('identity.verification_session.verified', { metadata: { wasiatiUserId: 'victim' } });
    expect(() => provider.parseWebhook(raw, 'v1=deadbeef,t=1')).toThrow(UnauthorizedException);
  });

  it('503s when no webhook secret is configured — never trusts the payload', () => {
    const bare = new StripeIdentityProvider(configWith({ STRIPE_WEBHOOK_SECRET: undefined }));
    const raw = event('identity.verification_session.verified');
    expect(() => bare.parseWebhook(raw, sign(raw))).toThrow(ServiceUnavailableException);
  });
});

describe('StripeIdentityProvider.parseWebhook — event mapping', () => {
  const provider = new StripeIdentityProvider(configWith());
  const parse = (raw: Buffer) => provider.parseWebhook(raw, sign(raw));

  it('maps verified -> VERIFIED', () => {
    expect(parse(event('identity.verification_session.verified')).status).toBe('VERIFIED');
  });

  it('maps requires_input -> REJECTED', () => {
    const raw = event('identity.verification_session.requires_input', {
      status: 'requires_input',
      last_error: { code: 'document_unverified_other', reason: 'The document could not be verified.' },
    });
    expect(parse(raw)).toEqual({ userId: 'user-1', status: 'REJECTED', providerRef: 'vs_1' });
  });

  it('maps processing and created -> PENDING', () => {
    expect(parse(event('identity.verification_session.processing', { status: 'processing' })).status).toBe('PENDING');
    expect(parse(event('identity.verification_session.created', { status: 'requires_input' })).status).toBe('PENDING');
  });

  it('IGNORES a lifecycle event instead of rejecting the user', () => {
    // A user who walked away has not failed KYC; canceling must not lock them out.
    const canceled = parse(event('identity.verification_session.canceled', { status: 'canceled' }));
    expect(canceled.ignored).toBe(true);
    expect(canceled.userId).toBe('');

    expect(parse(event('identity.verification_session.redacted')).ignored).toBe(true);
  });

  it('IGNORES an unrelated event type safely (a payments event posted here)', () => {
    const raw = Buffer.from(
      JSON.stringify({
        id: 'evt_pay',
        object: 'event',
        type: 'payment_intent.succeeded',
        data: { object: { object: 'payment_intent', id: 'pi_1' } },
      }),
    );
    const parsed = provider.parseWebhook(raw, sign(raw));
    expect(parsed.ignored).toBe(true);
    expect(parsed.userId).toBe('');
  });

  it('reads the user ONLY from what we stamped — falling back to client_reference_id', () => {
    const raw = event('identity.verification_session.verified', {
      metadata: {},
      client_reference_id: 'user-7',
    });
    expect(parse(raw).userId).toBe('user-7');
  });

  it('rejects a signed outcome that names no user rather than guessing', () => {
    const raw = event('identity.verification_session.verified', { metadata: {}, client_reference_id: null });
    expect(() => parse(raw)).toThrow(/no user reference/i);
  });
});

/**
 * Provider selection. This pulls the REAL useFactory out of IdentityModule's metadata
 * rather than restating its logic, so the test cannot drift away from what boots. The
 * property being pinned: a missing vendor degrades to the adapter that refuses, never
 * to one that approves.
 */
describe('IdentityModule provider selection', () => {
  const sumsubConfig = (over: Record<string, string | undefined> = {}) =>
    ({
      get: (k: string) =>
        ({
          SUMSUB_APP_TOKEN: 'app_tok',
          SUMSUB_SECRET_KEY: 'sk_test',
          SUMSUB_WEBHOOK_SECRET: 'whsec_sumsub',
          ...over,
        })[k],
    }) as unknown as ConfigService;

  const factory = (): ((...args: any[]) => IdentityProviderPort) => {
    const providers = (Reflect.getMetadata('providers', IdentityModule) ?? []) as any[];
    const entry = providers.find((p) => p && p.provide === IDENTITY_PROVIDER);
    expect(entry?.useFactory).toBeDefined();
    return entry.useFactory;
  };

  const pick = (stripe: StripeIdentityProvider, sumsub: SumsubIdentityProvider) =>
    factory()(stripe, sumsub, new UnconfiguredIdentityProvider());

  it('prefers Stripe Identity when its credentials exist', () => {
    const chosen = pick(new StripeIdentityProvider(configWith()), new SumsubIdentityProvider(sumsubConfig()));
    expect(chosen.name).toBe('STRIPE_IDENTITY');
  });

  it('falls back to Sumsub only when Stripe is absent', () => {
    const chosen = pick(
      new StripeIdentityProvider(configWith({ STRIPE_SECRET_KEY: undefined })),
      new SumsubIdentityProvider(sumsubConfig()),
    );
    expect(chosen.name).toBe('SUMSUB');
  });

  it('falls back to the 503 adapter when neither is configured — it does not throw at boot', () => {
    const stripe = new StripeIdentityProvider(configWith({ STRIPE_SECRET_KEY: '', STRIPE_WEBHOOK_SECRET: '' }));
    const sumsub = new SumsubIdentityProvider(sumsubConfig({ SUMSUB_APP_TOKEN: undefined }));

    let chosen!: ReturnType<typeof pick>;
    expect(() => {
      chosen = pick(stripe, sumsub);
    }).not.toThrow();
    expect(chosen.name).toBe('UNCONFIGURED');
    expect(chosen.configured).toBe(false);
    expect(() => (chosen as UnconfiguredIdentityProvider).parseWebhook()).toThrow(ServiceUnavailableException);
  });
});
