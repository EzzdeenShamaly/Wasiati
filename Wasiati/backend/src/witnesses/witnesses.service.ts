import { Injectable, BadRequestException, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appBaseUrl } from '../common/app-url';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OtpService } from '../auth/otp.service';
import { RedisService } from '../redis/redis.service';
import { withinOtpCeiling } from '../common/otp-ceiling';
import { assertWillNotExecuted } from '../common/will-executed';
import { WillsService } from '../wills/wills.service';

/**
 * Signing codes to ONE witness phone, per rolling hour and day. A witness signs once, so
 * this only has to survive genuine delivery retries — it is not a repeated login.
 */
const WITNESS_CODE_LIMITS = { perHour: 5, perDay: 15 };

@Injectable()
export class WitnessesService {
  private readonly logger = new Logger(WitnessesService.name);

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
    private otp: OtpService,
    private wills: WillsService,
    private config: ConfigService,
    private redis: RedisService,
  ) {}

  /** Confirms the will belongs to the caller. NotFound (not Forbidden) so we never
   *  disclose that another user's will exists. */
  private async assertWillOwner(willId: string, ownerId: string) {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
  }

  /** Will owner adds a witness by name + phone (+ optional email for reminders). */
  async addWitness(willId: string, ownerId: string, fullName: string, phone: string, email?: string) {
    await this.assertWillOwner(willId, ownerId);
    // A sealed will's witness roster is part of the executed document — see the reasoning
    // in common/will-executed.ts, which the trustee roster shares.
    await assertWillNotExecuted(this.prisma, willId);
    const witness = await this.prisma.witness.create({
      data: { willId, fullName, phone, email },
    });

    // Tell the witness they have been named. Previously they were added silently
    // and only heard from us when the owner manually pushed a signing code.
    //
    // `notified: false` is surfaced to the OWNER rather than swallowed: it means nobody
    // was reached, so the witness will never confirm and the will can never seal. The
    // owner is the only person who can fix it (correct the number, add an email), and
    // they cannot act on a failure they are not shown.
    const notified = await this.notifyWitnessInvited(
      witness.id,
      witness.fullName,
      witness.phone,
      witness.email,
    );
    return { ...witness, notified };
  }

  /** The public signing page for one witness row (same base-URL rule as the claim
   *  invite link, death-claims.service.ts:302). The id is NOT a bearer credential —
   *  the page can only text a code to the phone already on this roster row. */
  private signLink(witnessId: string): string {
    const base = appBaseUrl(this.config);
    return `${base.replace(/\/+$/, '')}/witness/${witnessId}`;
  }

  /**
   * Best-effort invite. A delivery failure must never prevent the witness being recorded
   * on the will — the owner can always resend the signing code.
   *
   * Returns whether ANY channel actually reached them. Best-effort must not mean
   * unobservable: `email` is optional on this roster while phone is required, so a
   * phone-only witness whose SMS never dispatched received NOTHING while the owner saw a
   * clean success. They then wait for a confirmation that was never requested, and the
   * will cannot reach its witness quorum — a silent dead end on the sealing path.
   */
  private async notifyWitnessInvited(
    witnessId: string,
    fullName: string,
    phone: string,
    email?: string | null,
  ): Promise<boolean> {
    const body =
      `${fullName}, you have been named as a witness on a Wasiati will. ` +
      `When you are asked to sign, open this link — a one-time code will be sent to this phone: ` +
      `${this.signLink(witnessId)}`;
    let delivered = false;
    try {
      delivered = await this.notifications.sendSms(phone, body);
    } catch (e) {
      this.logger.error(`Witness invite SMS to ${phone} failed: ${(e as Error).message}`);
    }
    if (email) {
      try {
        const mailed = await this.notifications.sendEmail(
          email,
          'You have been named a witness on a Wasiati will',
          body,
        );
        delivered = delivered || mailed;
      } catch (e) {
        this.logger.error(`Witness invite email to ${email} failed: ${(e as Error).message}`);
      }
    }
    if (!delivered) {
      this.logger.warn(`Witness ${witnessId} was reached by NO channel — the owner must be told.`);
    }
    return delivered;
  }

  /** Sends the witness their one-time signing code. */
  async sendSigningCode(witnessId: string) {
    const witness = await this.prisma.witness.findUnique({ where: { id: witnessId } });
    if (!witness) throw new NotFoundException('Witness not found.');
    // The code is delivered ONLY over SMS to the witness's phone; it must never be
    // returned in the HTTP response. This endpoint is unauthenticated (the witness may
    // not have a platform account), so echoing the live, consumable signing code here
    // would hand it to any anonymous caller who guesses/knows a witness id — defeating
    // the phone-possession check that gates the signature.
    //
    // The same reasoning bounds how OFTEN it may be sent. The route's @Throttle is keyed
    // by IP, so it bounds a caller and not the witness; and because verify only reads the
    // NEWEST code, repeated requests supersede the one already in the witness's hand. The
    // witnessId is a uuid rather than a guess, but it travels in the invitation link —
    // which is exactly the thing that gets forwarded into a family group chat. Anyone
    // holding it could otherwise bill unlimited SMS to that phone and keep the witness
    // permanently unable to sign.
    //
    // Silent when suppressed: the response is { sent: true } either way, because saying
    // "rate limited" would confirm a witness id is real.
    if (await withinOtpCeiling(this.redis, this.logger, 'witness:sign', witness.phone, WITNESS_CODE_LIMITS)) {
      await this.otp.issue(witness.phone, 'witness_sign');
    }
    return { sent: true };
  }

  /** Normalises a name for comparison: case, diacritics-insensitive, single spaces. */
  static normalizeName(name: string): string {
    return name
      .normalize('NFKD')
      .replace(/[ً-ٰٟ]/g, '') // Arabic harakat
      .replace(/[̀-ͯ]/g, '') // Latin combining marks
      .toLowerCase()
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Witness signs: OTP + a name-match against the will (spec §6). A signature is DIGITAL ONLY; there is no ink path.
   * NOTE: this is a NAME match against the name the testator recorded — not a
   * national-ID check. Do not represent it as government-ID verification. When
   * Nafath (KSA) or the KYC vendor is wired for witnesses, gate MATCHED on that.
   * The signature cannot complete unless the legal name they verify matches the name
   * the testator recorded, which sets the "ID MATCHED" state.
   */
  async confirmSignature(
    witnessId: string,
    code: string,
    signatureData: string,
    legalName: string,
    ipAddress: string,
    userAgent?: string,
  ) {
    const witness = await this.prisma.witness.findUnique({ where: { id: witnessId } });
    if (!witness) throw new NotFoundException('Witness not found.');

    const valid = await this.otp.verify(witness.phone, 'witness_sign', code);
    if (!valid) throw new BadRequestException('Invalid or expired code.');

    // AFTER the OTP, deliberately. This route is unauthenticated and the witness id travels
    // in an invitation link — the kind of thing that gets forwarded into a family group
    // chat — so the file is careful never to tell an unproven caller that an id is real.
    // Checking here means only someone who has proven possession of the witness's phone
    // learns anything, which is no disclosure at all, and the real witness gets an honest
    // reason instead of being turned away by a code that was never going to work.
    //
    // The cost of that ordering, stated: sendSigningCode still dispatches one SMS for a
    // will that has already sealed. Refusing earlier would be cheaper and would leak; the
    // destination ceiling above already bounds how many such messages are possible.
    await assertWillNotExecuted(this.prisma, witness.willId);

    const matched =
      WitnessesService.normalizeName(legalName ?? '') === WitnessesService.normalizeName(witness.fullName);
    if (!matched) {
      // Never record a signature that failed the identity check.
      throw new BadRequestException(
        'The legal name you entered does not match the name on this will, so the signature was not recorded.',
      );
    }

    const updated = await this.prisma.witness.update({
      where: { id: witnessId },
      data: {
        status: 'SIGNED',
        signedAt: new Date(),
        signatureData,
        ipAddress,
        userAgent,
        idMatchStatus: 'MATCHED',
      },
    });
    // Advance the will's lifecycle (SIGNED -> WITNESSED) once enough witnesses have signed.
    await this.wills.recomputeAfterWitness(witness.willId);
    return updated;
  }

  async listForWill(willId: string, ownerId: string) {
    await this.assertWillOwner(willId, ownerId);
    return this.prisma.witness.findMany({ where: { willId } });
  }
}
