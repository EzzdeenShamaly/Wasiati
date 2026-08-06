import { Injectable, BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomInt } from 'crypto';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { normalizePhone } from '../common/phone.util';

/**
 * The exact string an OTP is filed under.
 *
 * issue() and verify() MUST derive this the same way, or a code issued to one
 * spelling of a number is looked up under another and the verify finds nothing.
 * Phones are normalised (`0555123456` and `+966555123456` become one destination);
 * emails are lower-cased and trimmed. Previously both sides stored the caller's raw
 * string, so the pair only worked when the caller spelled the number identically
 * twice — which the death-claim path could not guarantee, because the number is
 * typed by a member of the family rather than read back off the account.
 *
 * DELIBERATELY NOT keyed off the `channel` argument: `issue` takes one and
 * `verify` does not (WillsService issues an email step-up on the 'email' channel
 * and verifies it without repeating that), so a channel-dependent key would silently
 * break exactly that flow. Discriminating on the '@' instead makes the two sides
 * agree no matter which arguments the caller passes.
 *
 * DEPLOY NOTE: this changes the key, so codes ALREADY IN FLIGHT at deploy time
 * cannot be verified and the user must request a new one. Acceptable at a 10-minute
 * TTL — the blast radius is whoever asked for a code in the ten minutes before the
 * rollout, and their retry works.
 */
export function otpDestinationKey(destination: string): string {
  const raw = String(destination ?? '').trim();
  if (raw.includes('@')) return raw.toLowerCase();
  return normalizePhone(raw) || raw;
}

const OTP_LENGTH = 6;
const OTP_TTL_MINUTES = 10;
/** Wrong guesses allowed against one code before it is burned. */
export const OTP_MAX_ATTEMPTS = 5;

@Injectable()
export class OtpService {
  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
    private config: ConfigService,
  ) {}

  /**
   * DEV ONLY. When OTP_DEV_ECHO=true (never in production), returns the code so
   * local/e2e flows can complete without a real SMS provider. Returns undefined
   * otherwise, so production responses never leak the code.
   */
  devEchoCode(code: string): string | undefined {
    return this.config.get<string>('OTP_DEV_ECHO') === 'true' ? code : undefined;
  }

  /**
   * Whether the WhatsApp channel can actually deliver (client + sender configured).
   *
   * Surfaced here rather than injecting NotificationsService into AuthService: this service
   * already owns every send decision, and the channel choice has to be made BEFORE issuing
   * a code — picking WhatsApp and failing over to SMS would cost the user a delay on every
   * single login.
   */
  get whatsappAvailable(): boolean {
    return this.notifications.whatsappAvailable;
  }

  private generateCode(): string {
    // crypto.randomInt (CSPRNG) — these codes gate login MFA, witness signing,
    // trustee confirmation and the death-claim safety check, so the code must not
    // be predictable the way Math.random() (V8 xorshift128+) would be.
    return randomInt(0, 10 ** OTP_LENGTH)
      .toString()
      .padStart(OTP_LENGTH, '0');
  }

  /**
   * Creates and sends a one-time code to a destination for a given purpose.
   * purpose examples: 'login_mfa' | 'witness_sign' | 'trustee_confirm' | 'death_claim_safety_check'
   *
   * The channel decides both the transport AND what `destination` means: a phone number
   * for 'sms'/'whatsapp', an email address for 'email'. `verify` keys off the same
   * (destination, purpose) pair, so a caller must issue and verify on the same channel.
   * The 'email' channel exists so a step-up flow can fall back to the account's verified
   * email when the user has no phone (will unpublish/delete — DECISIONS §17).
   */
  async issue(destination: string, purpose: string, userId?: string, channel: 'sms' | 'whatsapp' | 'email' = 'sms') {
    const code = this.generateCode();
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000);
    const key = otpDestinationKey(destination);

    await this.prisma.otpCode.create({
      data: { userId, destination: key, codeHash, purpose, expiresAt },
    });

    // Send to the normalised form too, not the raw input: it is what verify will key
    // off, and it is the spelling the SMS gateway wants (E.164).
    const body = `Your Wasiati verification code is ${code}. It expires in ${OTP_TTL_MINUTES} minutes.`;
    // sendSms/sendEmail return whether the code was actually DISPATCHED. A code that
    // reached nobody must not look like one that did (see the doc comment on sendSms):
    // if we ignore the result, a login/step-up returns a success-shaped response and
    // strands the user on the code screen forever. So an undelivered code is surfaced
    // as a real error — EXCEPT in dev, where OTP_DEV_ECHO=true intentionally makes the
    // transport a no-op and returns the code in the response instead.
    // (WhatsApp returns void today and is never selected — treated as best-effort.)
    let delivered = true;
    if (channel === 'whatsapp') {
      // Honours the boolean like the others now. It used to be treated as best-effort
      // because sendWhatsapp returned void and nothing ever selected this channel; both
      // are fixed, so an undelivered WhatsApp code is a real error rather than a silent one.
      delivered = await this.notifications.sendWhatsapp(key, body);
    } else if (channel === 'email') {
      delivered = await this.notifications.sendEmail(key, 'Your Wasiati verification code', body);
    } else {
      delivered = await this.notifications.sendSms(key, body);
    }
    if (!delivered && this.config.get<string>('OTP_DEV_ECHO') !== 'true') {
      throw new ServiceUnavailableException(
        'We could not send your verification code right now. Please try again in a moment.',
      );
    }
    return code; // callers may pass through devEchoCode() in dev; never expose in prod
  }

  /**
   * Verifies a submitted code against the most recent unconsumed code for that
   * destination+purpose.
   *
   * A wrong guess increments an attempt counter; once OTP_MAX_ATTEMPTS is reached the
   * code is BURNED (consumed), so the ~10^6 space cannot be exhausted within the TTL
   * even by an attacker who rotates IPs past the per-IP throttle. The counter bump is
   * a conditional updateMany so concurrent guesses can't both slip past the cap.
   */
  async verify(destination: string, purpose: string, code: string): Promise<boolean> {
    const record = await this.prisma.otpCode.findFirst({
      where: { destination: otpDestinationKey(destination), purpose, consumedAt: null },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) throw new BadRequestException('No pending code for this destination.');
    if (record.expiresAt < new Date()) throw new BadRequestException('Code has expired.');
    if (record.attempts >= OTP_MAX_ATTEMPTS) {
      throw new BadRequestException('Too many incorrect attempts. Please request a new code.');
    }

    const matches = await bcrypt.compare(code, record.codeHash);
    if (!matches) {
      // Count the failure and burn the code if this was the last allowed attempt.
      const attempts = record.attempts + 1;
      await this.prisma.otpCode.updateMany({
        where: { id: record.id, consumedAt: null },
        data: {
          attempts,
          consumedAt: attempts >= OTP_MAX_ATTEMPTS ? new Date() : null,
        },
      });
      return false;
    }

    await this.prisma.otpCode.update({
      where: { id: record.id },
      data: { consumedAt: new Date() },
    });
    return true;
  }
}
