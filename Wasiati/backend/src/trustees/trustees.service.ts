import { Injectable, BadRequestException, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appBaseUrl } from '../common/app-url';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OtpService } from '../auth/otp.service';
import { RedisService } from '../redis/redis.service';
import { withinOtpCeiling } from '../common/otp-ceiling';
import { assertWillNotExecuted } from '../common/will-executed';

/** Confirmation codes to ONE trustee phone, per rolling hour and day. See WITNESS_CODE_LIMITS. */
const TRUSTEE_CODE_LIMITS = { perHour: 5, perDay: 15 };

@Injectable()
export class TrusteesService {
  private readonly logger = new Logger(TrusteesService.name);

  constructor(
    private prisma: PrismaService,
    private otp: OtpService,
    private notifications: NotificationsService,
    private config: ConfigService,
    private redis: RedisService,
  ) {}

  /** Confirms the will belongs to the caller. NotFound (not Forbidden) so we never
   *  disclose that another user's will exists. */
  private async assertWillOwner(willId: string, ownerId: string) {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
  }

  // `ownerId` is the authenticated will owner (authorization); `userId` is the
  // trustee's own optional platform account (a different person).
  async addTrustee(willId: string, ownerId: string, fullName: string, phone: string, email?: string, userId?: string) {
    await this.assertWillOwner(willId, ownerId);
    // A sealed will's trustee is rendered on the executed document alongside the witnesses
    // — see common/will-executed.ts. Naming a new one afterwards rewrites it.
    await assertWillNotExecuted(this.prisma, willId);
    const trustee = await this.prisma.trustee.create({
      data: { willId, fullName, phone, email, userId },
    });
    // Tell the trustee they have been named, WITH the confirmation link.
    // Previously they were added silently and the app had nowhere for them to
    // confirm — so no trustee ever reached CONFIRMED outside of tests.
    // `notified: false` means nobody was reached, so this trustee will never confirm and
    // release can never be gated on them. Surfaced to the owner, who is the only person
    // who can correct the number or add an email.
    const notified = await this.notifyTrusteeInvited(
      trustee.id,
      trustee.fullName,
      trustee.phone,
      trustee.email,
    );
    return { ...trustee, notified };
  }

  /** The public confirmation page for one trustee row (same base-URL rule as the
   *  claim invite link, death-claims.service.ts:302). The id is NOT a bearer
   *  credential — the page it opens can only text a code to the phone already
   *  on this roster row. */
  private confirmLink(trusteeId: string): string {
    const base = appBaseUrl(this.config);
    return `${base.replace(/\/+$/, '')}/trustee/${trusteeId}`;
  }

  /**
   * Best-effort invite, mirroring the witness one (witnesses.service.ts): a
   * delivery failure must never prevent the trustee being recorded on the will.
   */
  private async notifyTrusteeInvited(
    trusteeId: string,
    fullName: string,
    phone: string,
    email?: string | null,
  ): Promise<boolean> {
    const body =
      `${fullName}, you have been named the trustee of a Wasiati will. ` +
      `Review the role and confirm here: ${this.confirmLink(trusteeId)}`;
    let delivered = false;
    try {
      delivered = await this.notifications.sendSms(phone, body);
    } catch (e) {
      this.logger.error(`Trustee invite SMS to ${phone} failed: ${(e as Error).message}`);
    }
    if (email) {
      try {
        const mailed = await this.notifications.sendEmail(
          email,
          'You have been named the trustee of a Wasiati will',
          body,
        );
        delivered = delivered || mailed;
      } catch (e) {
        this.logger.error(`Trustee invite email to ${email} failed: ${(e as Error).message}`);
      }
    }
    if (!delivered) {
      this.logger.warn(`Trustee ${trusteeId} was reached by NO channel — the owner must be told.`);
    }
    return delivered;
  }

  async sendConfirmationCode(trusteeId: string) {
    const trustee = await this.prisma.trustee.findUnique({ where: { id: trusteeId } });
    if (!trustee) throw new NotFoundException('Trustee not found.');
    // Delivered ONLY over SMS to the trustee's phone; never echoed in the response.
    // This endpoint is unauthenticated, so returning the live confirmation code would
    // hand a consumable code to any anonymous caller who knows a trustee id.
    //
    // And bounded per PHONE, not just per IP — see the note on WitnessesService.
    // sendSigningCode. A trustee confirmation is one of the gates release() requires, so
    // keeping a trustee from ever confirming is a way to freeze an estate rather than
    // merely annoy someone.
    if (await withinOtpCeiling(this.redis, this.logger, 'trustee:confirm', trustee.phone, TRUSTEE_CODE_LIMITS)) {
      await this.otp.issue(trustee.phone, 'trustee_confirm');
    }
    return { sent: true };
  }

  async confirm(trusteeId: string, code: string, ipAddress?: string, userAgent?: string) {
    const trustee = await this.prisma.trustee.findUnique({ where: { id: trusteeId } });
    if (!trustee) throw new NotFoundException('Trustee not found.');

    const valid = await this.otp.verify(trustee.phone, 'trustee_confirm', code);
    if (!valid) throw new BadRequestException('Invalid or expired code.');

    // AFTER the OTP, matching WitnessesService.confirmSignature: this route is
    // unauthenticated and the trustee id travels in an invitation link, so only a caller
    // who has proven possession of the trustee's phone is told anything about the will.
    //
    // Nobody is stranded by this. seal() refuses without a CONFIRMED trustee, so a will
    // that reached SEALED already has one — a confirmation arriving afterwards is a second
    // trustee answering late, or a duplicate, and neither belongs on an executed document.
    await assertWillNotExecuted(this.prisma, trustee.willId);

    return this.prisma.trustee.update({
      where: { id: trusteeId },
      // IP + user-agent captured for the completion certificate (evidentiary).
      data: { status: 'CONFIRMED', confirmedAt: new Date(), ipAddress, userAgent },
    });
  }

  async listForWill(willId: string, ownerId: string) {
    await this.assertWillOwner(willId, ownerId);
    return this.prisma.trustee.findMany({ where: { willId } });
  }
}
