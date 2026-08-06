import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { IdentityProviderPort, IdentityRedaction, IdentityVerificationSession } from '../identity-provider.interface';

/**
 * Placeholder KYC adapter for the US/CA rail.
 *
 * No KYC vendor is wired yet; the payment provider offers none.
 * This deliberately FAILS rather than no-ops: a KYC provider that
 * quietly approves everyone is worse than one that is honestly absent.
 *
 * Swap in an Onfido / Sumsub / Persona adapter and register it in IdentityModule.
 */
@Injectable()
export class UnconfiguredIdentityProvider implements IdentityProviderPort {
  readonly name = 'UNCONFIGURED';
  readonly configured = false;

  private fail(): never {
    throw new ServiceUnavailableException(
      'Identity verification is not available yet. Our team is enabling it — no action is needed from you.',
    );
  }

  createSession(): Promise<IdentityVerificationSession> {
    this.fail();
  }

  parseWebhook(): { userId: string; status: 'VERIFIED' | 'PENDING' | 'REJECTED' } {
    this.fail();
  }

  /**
   * Does NOT fail: nothing can have been collected through an adapter that refuses every
   * session, so there is nothing to redact and a purge must not be blocked by that. The
   * caller still guards the real risk — a user whose record says they verified on the
   * document rail while no such vendor is configured — because that means data exists
   * somewhere this deployment cannot reach.
   */
  async redactPersonalData(): Promise<IdentityRedaction> {
    return { provider: this.name, supported: false, sessionsFound: 0, redactionRequested: 0, alreadyRedacted: 0 };
  }
}
