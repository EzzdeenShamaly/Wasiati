import { BadRequestException, Injectable, Logger, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
// stripe's CJS build uses `export =`; this tsconfig has no esModuleInterop, so a
// default import would be `undefined` at runtime. import-equals is the safe form.
// (Same reasoning, same SDK instance version as payments/providers/stripe.provider.ts.)
import Stripe = require('stripe');
import { appBaseUrl } from '../../common/app-url';
import {
  IdentityOutcome,
  IdentityProviderPort,
  IdentityRedaction,
  IdentityVerificationSession,
  IdentityWebhookEvent,
} from '../identity-provider.interface';

/** Stripe's published upper bound for completing an accepted redaction. */
const REDACTION_MAX_DAYS = 4;

/**
 * Stripe Identity — document + selfie KYC for the US/CA rail (docs/DECISIONS.md §13,
 * which supersedes the §7 choice of Sumsub).
 *
 * Everything the owner asked for is Stripe's side of the line, not ours: document
 * capture, active liveness, the selfie, and the face-match against the ID all happen
 * on Stripe's hosted page. We create a VerificationSession, redirect the user to
 * `session.url`, and wait for a signed webhook. No image, no document number and no
 * biometric ever touches this server.
 *
 * Credentials are shared with the payments rail (STRIPE_SECRET_KEY /
 * STRIPE_WEBHOOK_SECRET) because it is the same Stripe account. Both are required
 * before this adapter reports `configured`: the outcome of a verification arrives
 * ONLY by webhook, so an instance that cannot verify a webhook signature could never
 * legitimately mark anyone VERIFIED. Missing or placeholder keys ⇒ `configured` is
 * false and IdentityModule falls back — the app still boots.
 *
 * KSA/QA are unaffected: Nafath is a separate, working rail (see NafathService).
 */
@Injectable()
export class StripeIdentityProvider implements IdentityProviderPort {
  readonly name = 'STRIPE_IDENTITY';
  private readonly logger = new Logger(StripeIdentityProvider.name);

  /** Lazy — constructed on first API call so the app boots without keys. */
  private sdk?: Stripe;
  /** Signature verification is pure HMAC (no network), so it must work whatever the
   *  API key is — mirrors StripeProvider.webhookVerifier(). */
  private verifier?: Stripe;

  /** Our user id, stamped on the session at creation and read back off the webhook. */
  static readonly USER_ID_KEY = 'wasiatiUserId';

  constructor(private config: ConfigService) {}

  /**
   * A credential is only usable when it has the right SHAPE. That doubles as
   * placeholder detection: `.env.example` ships these empty, and a half-filled
   * `STRIPE_SECRET_KEY=your_key_here` must degrade this adapter to "absent" rather
   * than crash at boot or 500 on the first user who taps "Verify my ID".
   * A false negative here costs an honest 503; a false positive would cost a
   * verification flow that dead-ends at Stripe. Prefer the 503.
   */
  private static usable(raw: string | undefined, prefixes: readonly string[]): string | undefined {
    const value = raw?.trim();
    if (!value) return undefined;
    if (!prefixes.some((p) => value.startsWith(p))) return undefined;
    if (value.length < 16) return undefined;
    if (/(xxxxxx|\.\.\.|[<>]|your[_-]?key|placeholder|changeme|todo)/i.test(value)) return undefined;
    return value;
  }

  /** `sk_` live/test secret key, or `rk_` restricted key. */
  private get secretKey(): string | undefined {
    return StripeIdentityProvider.usable(this.config.get<string>('STRIPE_SECRET_KEY'), ['sk_', 'rk_']);
  }

  private get webhookSecret(): string | undefined {
    return StripeIdentityProvider.usable(this.config.get<string>('STRIPE_WEBHOOK_SECRET'), ['whsec_']);
  }

  /** True only when a verification could actually be STARTED and FINISHED here. */
  get configured(): boolean {
    return !!(this.secretKey && this.webhookSecret);
  }

  private client(): Stripe {
    if (this.sdk) return this.sdk;
    const key = this.secretKey;
    if (!key) throw new ServiceUnavailableException('Identity verification is not configured on this server.');
    this.sdk = new Stripe(key);
    return this.sdk;
  }

  /** API-key-independent instance used only for webhook signature verification. */
  private webhookVerifier(): Stripe {
    if (this.verifier) return this.verifier;
    this.verifier = new Stripe(this.secretKey ?? 'sk_webhook_verify_only');
    return this.verifier;
  }

  /** Where Stripe sends the user back to once they are done with the hosted page. */
  private returnUrl(): string {
    const override = this.config.get<string>('STRIPE_IDENTITY_RETURN_URL')?.trim();
    return override || `${appBaseUrl(this.config)}/identity/verified`;
  }

  /**
   * Creates a VerificationSession and hands back Stripe's hosted URL.
   *
   * `url` is single-use and expires in 48h, so this is called per attempt rather than
   * cached. Our user id rides in `metadata` (and `client_reference_id` for the
   * Dashboard's benefit) — that is the ONLY thing the webhook trusts to name a user.
   */
  async createSession(params: { userId: string; email: string }): Promise<IdentityVerificationSession> {
    if (!this.configured) {
      throw new ServiceUnavailableException('Identity verification is not configured on this server.');
    }

    let session: Stripe.Identity.VerificationSession;
    try {
      session = await this.client().identity.verificationSessions.create({
        type: 'document',
        metadata: { [StripeIdentityProvider.USER_ID_KEY]: params.userId },
        client_reference_id: params.userId,
        // Shown to the user on Stripe's page; not a verification input.
        provided_details: { email: params.email },
        options: {
          document: {
            // No gallery uploads — the ID must be captured live by the device camera.
            require_live_capture: true,
            // The selfie + face-match against the ID. This is the check that makes a
            // stolen document photo useless, and it is why we do not build liveness.
            require_matching_selfie: true,
          },
        },
        return_url: this.returnUrl(),
      });
    } catch (e) {
      if (e instanceof ServiceUnavailableException) throw e;
      this.logger.error(`Stripe identity.verificationSessions.create failed: ${(e as Error).message}`);
      throw new ServiceUnavailableException('Could not reach Stripe Identity. Please try again.');
    }

    if (!session.url) {
      throw new ServiceUnavailableException('Stripe did not return a verification link.');
    }
    return { url: session.url, sessionId: session.id };
  }

  /**
   * Irreversibly redacts every verification session this user ever started.
   *
   * This is the only way the government-ID image and selfie actually leave Stripe. They
   * are the most sensitive artefacts in the product and they are NOT in our bucket, so
   * without this the posthumous tombstone would claim permanent deletion while the
   * passport photo sat at the vendor for years.
   *
   * Sessions are found by `client_reference_id` — which createSession() stamps with our
   * user id, and which is the ONLY server-side filter Stripe's list endpoint offers
   * (metadata is explicitly not filterable). Redaction is asynchronous, so what this
   * verifies is that the request was ACCEPTED; the vendor completes it within its own
   * published bound.
   */
  async redactPersonalData(userId: string): Promise<IdentityRedaction> {
    if (!this.configured) {
      return { provider: this.name, supported: false, sessionsFound: 0, redactionRequested: 0, alreadyRedacted: 0 };
    }
    const client = this.client();
    let sessionsFound = 0;
    let redactionRequested = 0;
    let alreadyRedacted = 0;
    let startingAfter: string | undefined;

    do {
      const page = await client.identity.verificationSessions.list({
        client_reference_id: userId,
        limit: 100,
        ...(startingAfter ? { starting_after: startingAfter } : {}),
      });
      for (const session of page.data) {
        sessionsFound++;
        // A session already redacted (or mid-redaction) must not be asked again —
        // redaction is irreversible and re-requesting it is pointless noise.
        if (session.redaction?.status) {
          alreadyRedacted++;
          continue;
        }
        await client.identity.verificationSessions.redact(session.id);
        redactionRequested++;
      }
      startingAfter = page.has_more ? page.data[page.data.length - 1]?.id : undefined;
    } while (startingAfter);

    this.logger.log(
      `Stripe Identity redaction for ${userId}: ${redactionRequested} requested, ${alreadyRedacted} already done, ` +
        `of ${sessionsFound} session(s).`,
    );
    return {
      provider: this.name,
      supported: true,
      sessionsFound,
      redactionRequested,
      alreadyRedacted,
      completesWithinDays: REDACTION_MAX_DAYS,
    };
  }

  /**
   * Event type → our status. Anything not listed is NOT a status change:
   *  · `.canceled` / `.redacted` are lifecycle bookkeeping — a user who walked away
   *    stays PENDING; they have not been rejected, and rejecting them would lock
   *    them out of a will they have paid for.
   *  · every other Stripe event (payments!) delivered here is simply not ours.
   */
  private static outcomeFor(type: string): IdentityOutcome | undefined {
    switch (type) {
      case 'identity.verification_session.verified':
        return 'VERIFIED';
      // Stripe's terminal failure: a check did not pass and the user must resubmit.
      case 'identity.verification_session.requires_input':
        return 'REJECTED';
      case 'identity.verification_session.processing':
      case 'identity.verification_session.created':
        return 'PENDING';
      default:
        return undefined;
    }
  }

  /**
   * Verifies `Stripe-Signature` over the RAW body, then maps the event.
   *
   * The signature is a timestamped HMAC over the exact bytes Stripe sent, so the route
   * must not JSON-parse first — main.ts registers `express.raw` for /identity/webhook
   * exactly as it does for /payments/webhook. `constructEvent` (the same call the
   * payments adapter uses) does the HMAC and the replay-window check and THROWS on a
   * bad, stale or missing signature. Nothing below runs on an unauthenticated payload.
   *
   * `algorithm` is part of the port for Sumsub's `x-payload-digest-alg`; Stripe
   * declares its scheme inside the header itself, so it is ignored here.
   */
  parseWebhook(rawBody: Buffer, signature: string): IdentityWebhookEvent {
    const secret = this.webhookSecret;
    if (!secret) {
      throw new ServiceUnavailableException('Identity webhooks are not configured on this server.');
    }

    let event: Stripe.Event;
    try {
      event = this.webhookVerifier().webhooks.constructEvent(rawBody, signature ?? '', secret);
    } catch {
      throw new UnauthorizedException('Invalid Stripe webhook signature.');
    }

    const status = StripeIdentityProvider.outcomeFor(event.type);
    if (!status) {
      // Signed and genuine, but not a verification outcome. Acknowledged so Stripe
      // stops retrying; writes nothing.
      this.logger.log(`Stripe identity webhook ignored: ${event.type}`);
      return { userId: '', status: 'PENDING', providerRef: event.id, ignored: true };
    }

    const session = event.data.object as Stripe.Identity.VerificationSession;
    // Recovered from what WE stamped at creation — never from anything a caller could
    // put in the payload. (The whole body is signature-verified, so these are ours.)
    const userId = session.metadata?.[StripeIdentityProvider.USER_ID_KEY] || session.client_reference_id || '';
    if (!userId) {
      throw new BadRequestException('Stripe identity webhook carried no user reference.');
    }

    if (status === 'REJECTED') {
      // The reason never reaches the user's record; log it so support can explain.
      this.logger.warn(
        `Stripe identity ${session.id} requires input: ${session.last_error?.code ?? 'no code'} — ` +
          `${session.last_error?.reason ?? 'no reason given'}`,
      );
    }
    this.logger.log(`Stripe identity webhook: session ${session.id} -> ${status}`);
    return { userId, status, providerRef: session.id };
  }
}
