import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { MailQueue } from '../mail/mail.queue';
import { TokenService } from './token.service';
import { OtpService } from './otp.service';
import { appBaseUrl } from '../common/app-url';

const VERIFY_TTL_MS = 24 * 60 * 60 * 1000; // 24h
const RESET_TTL_MS = 60 * 60 * 1000; // 1h

/** OtpService purpose for the code-based reset. Keyed with the destination, never the id. */
export const PASSWORD_RESET_PURPOSE = 'password_reset';

/**
 * Email verification and password reset.
 *
 * Both flows use single-use, hashed, expiring tokens (we store only the SHA-256
 * hash; the raw token travels only in the emailed link). To avoid leaking whether
 * an email is registered, the "request" endpoints always report success.
 * A successful password reset revokes ALL of the user's refresh tokens so any
 * stolen session is invalidated.
 */
@Injectable()
export class AccountRecoveryService {
  private readonly logger = new Logger(AccountRecoveryService.name);

  constructor(
    private prisma: PrismaService,
    private mail: MailQueue,
    private tokens: TokenService,
    private config: ConfigService,
    private otp: OtpService,
  ) {}

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  /**
   * Shared with every other outbound link (common/app-url.ts). This file used to read
   * APP_WEB_URL while six other services read APP_BASE_URL — two names for one concept,
   * and only this one was ever defined. That is exactly why password-reset mails pointed
   * at localhost correctly while every trustee, witness and claim link pointed at
   * production and could not be tested.
   */
  private get webUrl(): string {
    return appBaseUrl(this.config);
  }

  // --- email verification --------------------------------------------------

  async issueEmailVerification(userId: string, email: string): Promise<void> {
    const raw = randomBytes(32).toString('base64url');
    await this.prisma.emailVerificationToken.create({
      data: { userId, tokenHash: this.hash(raw), expiresAt: new Date(Date.now() + VERIFY_TTL_MS) },
    });
    const link = `${this.webUrl}/verify-email?token=${raw}`;
    await this.mail.enqueue({
      to: email,
      subject: 'Verify your Wasiati email',
      text: `Welcome to Wasiati. Confirm your email address:\n\n${link}\n\nThis link expires in 24 hours.`,
      html: `<p>Welcome to Wasiati. Confirm your email address:</p><p><a href="${link}">Verify my email</a></p><p>This link expires in 24 hours.</p>`,
    });
  }

  async verifyEmail(rawToken: string): Promise<{ verified: true }> {
    const record = await this.prisma.emailVerificationToken.findUnique({ where: { tokenHash: this.hash(rawToken) } });
    if (!record || record.consumedAt || record.expiresAt < new Date()) {
      throw new BadRequestException('Verification link is invalid or has expired.');
    }
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: record.userId }, data: { emailVerified: true } }),
      this.prisma.emailVerificationToken.update({ where: { id: record.id }, data: { consumedAt: new Date() } }),
    ]);
    return { verified: true };
  }

  /** Always returns success (no account-existence disclosure). */
  async resendVerification(email: string): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (user && !user.emailVerified) {
      await this.issueEmailVerification(user.id, user.email);
    }
  }

  // --- password reset ------------------------------------------------------

  /** Always returns success (no account-existence disclosure). */
  async requestPasswordReset(email: string): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !user.passwordHash) return; // OAuth-only accounts have no password to reset
    const raw = randomBytes(32).toString('base64url');
    await this.prisma.passwordResetToken.create({
      data: { userId: user.id, tokenHash: this.hash(raw), expiresAt: new Date(Date.now() + RESET_TTL_MS) },
    });
    const link = `${this.webUrl}/reset-password?token=${raw}`;
    await this.mail.enqueue({
      to: user.email,
      subject: 'Reset your Wasiati password',
      text: `We received a request to reset your password:\n\n${link}\n\nThis link expires in 1 hour. If you didn't request this, ignore this email.`,
      html: `<p>We received a request to reset your password:</p><p><a href="${link}">Reset my password</a></p><p>This link expires in 1 hour. If you didn't request this, you can safely ignore this email.</p>`,
    });
  }

  // --- password reset by one-time code -------------------------------------

  /**
   * Where a reset code goes: the phone when there is one, otherwise the email.
   *
   * Same resolution as login MFA (AuthService.mfaChannel) and will step-up
   * (WillsService.stepUpChannel), so issue and verify can never key off different
   * destinations — a bug both of those shipped with at some point.
   */
  private resetChannel(user: { phone: string | null; email: string }): {
    destination: string;
    channel: 'sms' | 'email';
  } {
    return user.phone ? { destination: user.phone, channel: 'sms' } : { destination: user.email, channel: 'email' };
  }

  /**
   * Sends a one-time reset code instead of a link.
   *
   * WHY A CODE AND NOT A LINK: the emailed link is a bearer credential. Anyone holding
   * that mail — a forwarded thread, a shared family inbox, a synced device — can take over
   * the account, and a will platform has more shared inboxes than most. A code must be
   * typed into the session that asked for it, and when the user has a phone it moves the
   * reset onto a second channel entirely, so compromising the mailbox alone is no longer
   * enough. Consistent with the owner's login decision (f242634): a password is never
   * sufficient on its own.
   *
   * ALWAYS resolves silently — an unknown address, an OAuth-only account and a real user
   * are indistinguishable to the caller, exactly like the link flow.
   */
  async requestPasswordResetCode(email: string): Promise<{ sent: true }> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (user?.passwordHash) {
      const { destination, channel } = this.resetChannel(user);
      await this.otp.issue(destination, PASSWORD_RESET_PURPOSE, user.id, channel);
    }
    // Deliberately no `via` in the response. Telling an anonymous caller "we texted them"
    // versus "we emailed them" discloses whether the account has a phone on file, and
    // whether it exists at all. The user knows where their own code went.
    return { sent: true };
  }

  /**
   * Verifies the code and sets the new password. Same post-conditions as the link flow:
   * every existing session is revoked, so a reset logs out all devices.
   */
  async resetPasswordWithCode(email: string, code: string, newPassword: string): Promise<{ reset: true }> {
    const user = await this.prisma.user.findUnique({ where: { email } });
    // One message for every failure — unknown address, OAuth-only account, wrong code,
    // expired code, attempts burned. Distinguishable errors here would turn this endpoint
    // into an account-existence oracle, which is the property the request step protects.
    const invalid = new BadRequestException('That code is invalid or has expired.');
    if (!user?.passwordHash) throw invalid;

    const { destination } = this.resetChannel(user);
    let ok = false;
    try {
      ok = await this.otp.verify(destination, PASSWORD_RESET_PURPOSE, code);
    } catch {
      throw invalid; // OtpService throws distinguishable messages; collapse them.
    }
    if (!ok) throw invalid;

    const passwordHash = await bcrypt.hash(newPassword, 12);
    await this.prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
    await this.tokens.revokeAllForUser(user.id);
    return { reset: true };
  }

  async resetPassword(rawToken: string, newPassword: string): Promise<{ reset: true }> {
    const record = await this.prisma.passwordResetToken.findUnique({ where: { tokenHash: this.hash(rawToken) } });
    if (!record || record.consumedAt || record.expiresAt < new Date()) {
      throw new BadRequestException('Reset link is invalid or has expired.');
    }
    const passwordHash = await bcrypt.hash(newPassword, 12);
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: record.userId }, data: { passwordHash } }),
      this.prisma.passwordResetToken.update({ where: { id: record.id }, data: { consumedAt: new Date() } }),
    ]);
    // Invalidate every existing session — a password reset should log out all devices.
    await this.tokens.revokeAllForUser(record.userId);
    return { reset: true };
  }
}
