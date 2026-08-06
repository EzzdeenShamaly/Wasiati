/**
 * The seam for document/selfie KYC on the US/CA rail.
 *
 * Stripe Identity is the chosen vendor (docs/DECISIONS.md §13, superseding the §7
 * choice of Sumsub, whose adapter is kept behind this same port as a fallback). It is
 * config-gated: without credentials the module falls back to
 * UnconfiguredIdentityProvider, which refuses loudly (503) rather than no-op — an
 * identity provider that quietly approves everyone is worse than one that is honestly
 * absent.
 *
 * KSA/QA are unaffected — Nafath is a separate, working rail (see NafathService).
 */
export interface IdentityVerificationSession {
  /** Hosted URL the user is redirected to for document capture. */
  url: string;
  /** Provider-side session id, for reconciliation. */
  sessionId: string;
}

export type IdentityOutcome = 'VERIFIED' | 'PENDING' | 'REJECTED';

export interface IdentityWebhookEvent {
  userId: string;
  status: IdentityOutcome;
  /** Provider-side applicant/session id, for audit. */
  providerRef?: string;
  /**
   * Set for a signature-VERIFIED event we deliberately do not act on — Stripe
   * delivers session lifecycle events (`.canceled`, `.redacted`) and, on a shared
   * endpoint, unrelated ones. The service acknowledges it with a 200 so the provider
   * stops retrying, and writes nothing. `status` is meaningless when this is true.
   */
  ignored?: boolean;
}

/**
 * What a redaction run did, recorded in the posthumous purge tombstone.
 *
 * The government-ID scan and selfie are the most sensitive artefacts the product ever
 * touches, and they do NOT live in our storage — the vendor holds them. Erasing our own
 * bucket while the vendor keeps the passport photo for years would make "permanently
 * deleted" false in the place it matters most.
 */
// A `type` rather than an `interface` on purpose: this object is written straight into
// the DataPurgeLog's Json column, and Prisma's InputJsonValue only accepts types with an
// implicit index signature — which TypeScript gives to type aliases but not interfaces.
export type IdentityRedaction = {
  provider: string;
  /** False when the vendor offers no programmatic redaction (or none is configured). */
  supported: boolean;
  sessionsFound: number;
  /** Sessions we asked the vendor to redact on this run. */
  redactionRequested: number;
  /** Sessions the vendor had already redacted (or was already redacting). */
  alreadyRedacted: number;
  /**
   * Redaction is ASYNCHRONOUS at Stripe — documented as taking up to four days, with the
   * session moving to `redaction.status: 'redacted'` and firing
   * `identity.verification_session.redacted` when it finishes. So unlike the storage
   * sweep, what we can verify here is that the REQUEST was accepted, not that the bytes
   * are already gone. This records the vendor's bound so the tombstone can say so
   * plainly rather than implying an instant erasure it did not perform.
   */
  completesWithinDays?: number;
}

export interface IdentityProviderPort {
  readonly name: string;
  readonly configured: boolean;

  createSession(params: { userId: string; email: string }): Promise<IdentityVerificationSession>;

  /**
   * Irreversibly redacts every verification session belonging to this user at the
   * vendor. Called by the posthumous purge. Throws if the vendor refuses — the purge
   * treats that as a reason to abort and retry, never to claim erasure anyway.
   */
  redactPersonalData(userId: string): Promise<IdentityRedaction>;

  /**
   * Verifies the signature and maps the payload onto a user + outcome. Throws if the
   * signature does not match — an unverified webhook must never move a KYC status.
   *
   * `algorithm` carries the provider's declared digest algorithm where it sends one
   * (Sumsub's `x-payload-digest-alg`); adapters that don't need it ignore it.
   */
  parseWebhook(rawBody: Buffer, signature: string, algorithm?: string): IdentityWebhookEvent;
}

export const IDENTITY_PROVIDER = Symbol('IDENTITY_PROVIDER');
