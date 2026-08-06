import { BadRequestException, Inject, Injectable, Logger } from '@nestjs/common';
import { IdVerificationProvider, Prisma, VerificationStatus } from '@prisma/client';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { IDENTITY_PROVIDER, IdentityProviderPort } from './identity-provider.interface';

/**
 * ID verification / KYC for the US and Canada.
 *
 * The provider sits behind IdentityProviderPort; Stripe Identity implements it, with
 * Sumsub kept as a fallback. When neither has credentials the module supplies
 * UnconfiguredIdentityProvider instead, which throws a clean 503 rather than
 * approving anyone.
 *
 * `status()` still works either way — it reads what we already know about the user —
 * so the app can show "unverified" honestly instead of erroring on every page.
 *
 * KSA/QA use Nafath, which is unaffected.
 */
@Injectable()
export class IdentityService {
  private readonly logger = new Logger(IdentityService.name);

  constructor(
    private prisma: PrismaService,
    @Inject(IDENTITY_PROVIDER) private provider: IdentityProviderPort,
  ) {}

  /** True when a real KYC vendor is wired up. Lets the UI hide the CTA. */
  get available(): boolean {
    return this.provider.configured;
  }

  async createSession(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found.');

    // Throws a clean 503 while no vendor is configured.
    const session = await this.provider.createSession({ userId, email: user.email });

    await this.prisma.user.update({
      where: { id: userId },
      data: {
        idVerificationStatus: VerificationStatus.PENDING,
        // Record the rail as soon as the session starts, not only when the webhook
        // lands: a verification that is abandoned should still say WHICH rail the
        // user is on. Every adapter behind this port is a document vendor (Stripe
        // Identity, Sumsub); Nafath sets NAFATH on its own path and never gets here.
        idVerificationProvider: IdVerificationProvider.DOCUMENT,
      },
    });
    return { url: session.url, sessionId: session.sessionId };
  }

  /**
   * Posthumous-purge hook: irreversibly redacts the VENDOR's copy of this user's identity
   * documents. The ID image and selfie never touch our storage, so erasing our bucket
   * alone would leave the most sensitive artefact in the product sitting at the vendor.
   */
  async redactPersonalData(userId: string) {
    return this.provider.redactPersonalData(userId);
  }

  async status(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { idVerificationStatus: true },
    });
    return {
      status: user?.idVerificationStatus ?? VerificationStatus.UNVERIFIED,
      provider: this.provider.name,
      available: this.provider.configured,
    };
  }

  /**
   * Provider webhook → user.idVerificationStatus. The adapter verifies the signature
   * and throws on mismatch, so an unsigned or forged payload can never mark a user
   * VERIFIED. `updateMany` is used so an event naming an unknown user is a no-op
   * rather than a 500 that makes the provider retry forever.
   */
  async handleWebhook(rawBody: Buffer, signature: string, algorithm?: string) {
    // Signature verified inside parseWebhook (throws on mismatch).
    const { userId, status, providerRef, ignored } = this.provider.parseWebhook(rawBody, signature, algorithm);

    // Genuine, signed, and not a verification outcome (Stripe posts session
    // lifecycle events too). 200 so the provider stops retrying; nothing is written,
    // so it can never be the path that moves a KYC status.
    if (ignored) {
      this.logger.log(`Identity webhook ignored (${providerRef ?? 'no ref'}) — no status change.`);
      return { received: true, ignored: true };
    }

    // Replay protection: claim the event by a hash of the raw signed body. A captured
    // "VERIFIED" webhook replayed later (to undo a KYC revocation) hashes the same and
    // is a no-op. Insert-first so concurrent deliveries can't both process.
    const eventId = createHash('sha256').update(rawBody).digest('hex');
    try {
      await this.prisma.processedIdentityEvent.create({ data: { id: eventId, status } });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        this.logger.warn(`Identity webhook replay ignored (${providerRef ?? 'no ref'}).`);
        return { received: true, duplicate: true };
      }
      throw e;
    }

    const { count } = await this.prisma.user.updateMany({
      where: { id: userId },
      data: {
        idVerificationStatus: VerificationStatus[status],
        idVerificationProvider: IdVerificationProvider.DOCUMENT,
      },
    });
    if (count === 0) {
      this.logger.warn(`Identity webhook for unknown user ${userId} (${providerRef ?? 'no ref'}) — ignored.`);
      return { received: true };
    }

    this.logger.log(`Identity (${this.provider.name}) for user ${userId} -> ${status}`);
    return { received: true };
  }
}
