import {
  Injectable,
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService, otpDestinationKey } from './otp.service';
import { TokenService, AuthContext, SessionUser } from './token.service';
import { AccountRecoveryService } from './account-recovery.service';
import { TotpService } from './totp.service';
import { RecoveryCodesService } from './recovery-codes.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { AuthProvider, Region } from '@prisma/client';
import { assertResidency, countryToRegion, deploymentRegion, ResidencyViolationError } from '../common/geo.util';
import { validateAddress } from '../common/address-format';
import { isSaudiPhone, normalizePhone } from '../common/phone.util';

/** OtpService purpose for the login second factor. One string, one bucket. */
export const LOGIN_MFA_PURPOSE = 'login_mfa';

/**
 * Proving the number given at signup. A SEPARATE bucket from the login factor on purpose:
 * sharing one would let a signup verification consume the login allowance (and the reverse),
 * so a user who mistyped their number once could be locked out of signing in.
 */
export const PHONE_VERIFY_PURPOSE = 'phone_verify';

/**
 * How long the password step stays "proved" for the purposes of asking for another code.
 *
 * DELIBERATELY LONGER than OTP_TTL_MINUTES (10). The whole point of resend is the user
 * whose code expired; if the challenge died with the code, the only person who needs the
 * feature would be the one person who cannot use it.
 */
export const LOGIN_CHALLENGE_TTL_MS = 15 * 60 * 1000;

/**
 * Minimum gap between two login codes to one destination. Matches the client countdown.
 *
 * Overridable ONLY so a developer can exercise the login flow repeatedly. Manual testing
 * burns the hourly cap in minutes and then looks exactly like a wrong password — the
 * account is refused at the password step with a message about codes, which reads as
 * "credentials rejected" to anyone not holding this file open. Defaults are unchanged, so
 * production behaves identically unless the environment says otherwise.
 */
export const LOGIN_MFA_COOLDOWN_MS_DEFAULT = 30 * 1000;

/**
 * Read per call, NOT captured in a module-level const: these are evaluated at import time,
 * which happens before ConfigModule has loaded .env into process.env — so an override read
 * as undefined and the default silently won. The throttle config hit the same trap.
 */
export function loginMfaCooldownMs(): number {
  const v = Number(process.env.LOGIN_MFA_COOLDOWN_MS);
  return Number.isFinite(v) && v >= 0 ? v : LOGIN_MFA_COOLDOWN_MS_DEFAULT;
}
export function loginMfaMaxPerWindow(): number {
  const v = Number(process.env.LOGIN_MFA_MAX_PER_WINDOW);
  return Number.isFinite(v) && v > 0 ? v : 5;
}

/** Kept for tests and callers that want the shipped defaults. */
export const LOGIN_MFA_COOLDOWN_MS = LOGIN_MFA_COOLDOWN_MS_DEFAULT;

/** Login codes allowed per destination per rolling hour, counting the one login itself sends. */
export const LOGIN_MFA_MAX_PER_WINDOW = 5;
export const LOGIN_MFA_WINDOW_MS = 60 * 60 * 1000;

export interface AuthSuccess {
  accessToken: string;
  refreshToken: string;
  user: SessionUser;
}
export interface MfaChallenge {
  mfaRequired: true;
  userId: string;
  /**
   * Which channel the code went to, so the client can say "we texted you" vs "we emailed
   * you" — or, for `totp`, that NOTHING was sent and the code is already in their
   * authenticator app. Telling them to wait for a text that will never arrive is the
   * failure this field exists to prevent.
   */
  via: 'sms' | 'email' | 'totp' | 'whatsapp';
  /**
   * Opaque bearer proof that THIS caller just passed the password step. The only thing
   * POST /auth/login/resend-mfa accepts; it carries no user identifier of its own.
   *
   * Safe to hand to this caller and nobody else: whoever receives this response has
   * already typed the correct password, so it grants them nothing they could not obtain
   * by logging in again. That is the same reasoning that lets `via` be truthful here
   * while requestPasswordResetCode (anonymous caller) deliberately omits it.
   */
  challengeToken: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  /**
   * A constant, real bcrypt hash (cost 12 — the same cost register() uses) that no
   * password will ever match. On the account-not-found path we run a throwaway
   * bcrypt.compare against this so login spends the same ~300ms whether or not the
   * email exists. Without it, a missing account returns almost instantly while an
   * existing one pays for the hash, and that timing delta lets an attacker enumerate
   * which emails have accounts even though the body/status are identical.
   */
  private static readonly DUMMY_PASSWORD_HASH =
    '$2a$12$zx0c.9eynqIdrLPiQfVfBedo4/H8HY8qHIhC/756Qr5RnF5US2O7y';

  constructor(
    private prisma: PrismaService,
    private otp: OtpService,
    private tokens: TokenService,
    private recovery: AccountRecoveryService,
    private totp: TotpService,
    private recoveryCodes: RecoveryCodesService,
  ) {}

  // --- recovery codes -------------------------------------------------------

  /**
   * Issues a fresh set of backup codes, invalidating any previous one.
   *
   * Returned in plaintext exactly once — there is nowhere to look them up again, which is
   * what makes a stolen database useless for bypassing MFA.
   */
  regenerateRecoveryCodes(userId: string) {
    return this.recoveryCodes.regenerate(userId);
  }

  /** How many codes remain, for the security screen's nag. */
  recoveryCodesStatus(userId: string) {
    return this.recoveryCodes.status(userId);
  }

  // --- authenticator app (TOTP) enrolment -----------------------------------

  /**
   * Step one of enrolling an authenticator: hand back a secret to scan.
   *
   * Deliberately does NOT enable anything. A secret shown but never scanned would
   * otherwise lock the account behind a code the owner cannot produce — the failure mode
   * that makes people distrust 2FA. It becomes real only once they prove it works.
   */
  async startTotpEnrollment(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
    if (!user) throw new UnauthorizedException('Invalid session.');
    const secret = this.totp.generateSecret();
    return { secret, otpauthUri: this.totp.provisioningUri(user.email, secret), enabled: false };
  }

  /**
   * Step two: the owner types a code from the app, proving the secret arrived intact, and
   * only then is it stored (sealed) and switched on.
   */
  async enableTotp(userId: string, secret: string, code: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { mfaEnabled: true } });
    if (!user) throw new UnauthorizedException('Invalid session.');
    if (!secret || !this.totp.verify(secret, code)) {
      throw new BadRequestException('That code did not match. Check your authenticator app and try again.');
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { mfaSecret: this.totp.seal(secret), mfaEnabled: true },
    });
    return { enabled: true };
  }

  /**
   * Turns the authenticator off, and requires a current code to do it.
   *
   * Downgrading your own second factor is exactly what an attacker holding a live session
   * would do first, so it costs the same proof as using it. Afterwards the account falls
   * back to the SMS/email channel rather than to nothing — MFA stays mandatory.
   */
  async disableTotp(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { mfaEnabled: true, mfaSecret: true },
    });
    if (!user) throw new UnauthorizedException('Invalid session.');
    if (!user.mfaEnabled || !user.mfaSecret) throw new BadRequestException('No authenticator app is set up.');
    if (!this.totp.verify(this.totp.open(user.mfaSecret) ?? '', code)) {
      throw new BadRequestException('That code did not match.');
    }
    await this.prisma.user.update({ where: { id: userId }, data: { mfaSecret: null, mfaEnabled: false } });
    return { enabled: false };
  }

  /** Whether this account has an authenticator enrolled — for the security screen. */
  async totpStatus(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { mfaEnabled: true, mfaSecret: true },
    });
    return { enabled: !!(user?.mfaEnabled && user.mfaSecret) };
  }

  /**
   * Data residency is enforced here, at the only place personal data enters the
   * system. Each region has its own deployment + database; a user for another
   * region must be created on that region's service, not this one.
   */
  private guardResidency(region: Region): void {
    try {
      assertResidency(region);
    } catch (e) {
      if (e instanceof ResidencyViolationError) throw new BadRequestException(e.message);
      throw e;
    }
  }

  async register(dto: RegisterDto, ctx: AuthContext = {}): Promise<AuthSuccess> {
    // The region is DERIVED from where the user says they live, never taken from the
    // client's `region` field. That field was only ever the Flutter build's own
    // compile-time constant, so the old check compared the deployment to itself and
    // passed for everyone — a Saudi resident signing up on the US build was filed as
    // a US user, permanently (region is immutable). Address country is what the user
    // deliberately typed on this same form, it is what the data-protection laws key
    // on ("residing in KSA" — PDPL), and unlisted countries fall back to US, the
    // catch-all market. dto.region is retained in the DTO for client compatibility
    // but is deliberately ignored here.
    const region = countryToRegion(dto.addressCountry);
    this.guardResidency(region);

    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists.');

    // Address rules are per-country, so they cannot live on the DTO: a postal code is
    // mandatory in the US and Canada, absent in Qatar, optional in Saudi Arabia. The
    // offending FIELD NAMES come back so the client can mark the individual inputs rather
    // than putting one unhelpful banner over the whole form.
    const addressErrors = validateAddress(dto);
    if (addressErrors.length) {
      throw new BadRequestException({ message: 'Please check the address fields.', fields: addressErrors });
    }

    // Normalised to E.164 against the country the user just gave, so the number stored is
    // the number dialled. The raw string is never trusted: "0555 123456" is a different
    // number depending on where it was typed, and the login second factor, the witness and
    // trustee invitations and the death-claim lookup all key off this value.
    const phone = normalizePhone(dto.phone, dto.addressCountry ?? dto.region);

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        region,
        phone,
        // Deliberately NOT set — the number is unproven until the signup OTP is answered.
        // Stamping it at creation would make every typo look confirmed.
        phoneVerifiedAt: null,
        addressLine1: dto.addressLine1.trim(),
        addressLine2: dto.addressLine2?.trim() || null,
        addressCity: dto.addressCity.trim(),
        addressArea: dto.addressArea?.trim() || null,
        addressPostalCode: dto.addressPostalCode?.trim() || null,
        addressCountry: dto.addressCountry.toUpperCase(),
        authProvider: AuthProvider.EMAIL,
      },
    });

    // Send the verification email, but never fail registration if mail delivery
    // hiccups — the user can request a resend.
    try {
      await this.recovery.issueEmailVerification(user.id, user.email);
    } catch (e) {
      this.logger.warn(`Failed to send verification email to ${user.email}: ${(e as Error).message}`);
    }

    return this.tokens.issueTokenPair(this.toSessionUser(user), ctx);
  }

  /** Step 1 of login: verify password, then require MFA before issuing tokens.
   *  `_ctx` is unused BY DESIGN: no tokens are issued here — that happens in
   *  verifyMfaAndLogin, which receives its own context. Kept in the signature so the
   *  controller's call shape is uniform across every login entry point. */
  async validatePassword(dto: LoginDto, _ctx: AuthContext = {}): Promise<AuthSuccess | MfaChallenge> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (!user || !user.passwordHash) {
      // Spend the same time as a real password check so response time can't reveal
      // that the account is absent (see DUMMY_PASSWORD_HASH). Result is discarded.
      await bcrypt.compare(dto.password, AuthService.DUMMY_PASSWORD_HASH);
      throw new UnauthorizedException('Invalid credentials.');
    }

    const matches = await bcrypt.compare(dto.password, user.passwordHash);
    if (!matches) throw new UnauthorizedException('Invalid credentials.');

    // A password is NEVER sufficient on its own (owner decision, 20 Jul 2026). It used to
    // be gated on `user.mfaEnabled && user.phone`, and NOTHING in the product could set
    // mfaEnabled to true — no endpoint, no setting, no seed — so the second factor was
    // unreachable and this whole branch was dead code. A single reusable password was the
    // only thing standing between an attacker and someone's will.
    //
    // Passkeys are exempt (they carry their own possession proof and do not come through
    // here), as is OAuth, where the provider has already done strong auth.
    const { channel } = await this.issueLoginMfa(user);
    return {
      mfaRequired: true,
      userId: user.id,
      via: channel,
      challengeToken: await this.mintLoginChallenge(user.id),
    };
  }

  // --- login MFA code issuance ---------------------------------------------

  /**
   * The ONLY place a login_mfa code is ever sent. Both call sites — the password step and
   * the resend endpoint — go through here, on purpose: a cap that lives at one call site is
   * a cap an attacker reaches by using the other call site.
   *
   * That is not hypothetical. Before this existed, POST /auth/login had a per-IP throttle of
   * 8/minute and NO per-destination limit at all, so anyone holding one victim's password
   * could pump SMS at their phone indefinitely (and rotate IPs to beat the throttle). Adding
   * a resend endpoint with its own private counters would have left that hole open and
   * called it capped. Counting rows in OtpCode instead of counting requests is what makes
   * the limits survive IP rotation, and it needs no Redis.
   *
   * Both limits are checked BEFORE the send, and both raise 429 with ONE message — a caller
   * at the cooldown and a caller at the hourly cap learn nothing different about the account.
   */
  private async issueLoginMfa(user: {
    id: string;
    phone: string | null;
    email: string;
  }): Promise<{ destination: string; channel: 'sms' | 'email' | 'totp' | 'whatsapp' }> {
    const { destination, channel } = this.mfaChannel(user);
    // An authenticator needs nothing sent to it: the code is already on the user's device.
    // Returning early skips the OTP row, the message, and the per-destination cap — all of
    // which exist to govern something we are not doing.
    if (channel === 'totp') return { destination, channel };
    // Count against the NORMALISED key, never the raw spelling: otherwise '0555123456' and
    // '+966555123456' are two buckets for one phone and the cap is trivially doubled.
    const key = otpDestinationKey(destination);
    const now = Date.now();

    const [recent, issuedThisHour] = await Promise.all([
      this.prisma.otpCode.findFirst({
        where: { destination: key, purpose: LOGIN_MFA_PURPOSE },
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true },
      }),
      this.prisma.otpCode.count({
        where: {
          destination: key,
          purpose: LOGIN_MFA_PURPOSE,
          createdAt: { gte: new Date(now - LOGIN_MFA_WINDOW_MS) },
        },
      }),
    ]);

    const cooling = recent != null && now - recent.createdAt.getTime() < loginMfaCooldownMs();
    if (cooling || issuedThisHour >= loginMfaMaxPerWindow()) {
      // 429, never 200-with-nothing-sent. An endpoint that reports success for a message it
      // did not send teaches the client to restart a countdown for a code that will never
      // arrive; the always-200 pattern is right for ANONYMOUS endpoints (forgot-code) and
      // wrong here, where the caller has already proved the password.
      throw new HttpException('Too many codes requested. Please wait.', HttpStatus.TOO_MANY_REQUESTS);
    }

    // A benign check-then-create race at the boundary can let a 6th through. Accepted: the
    // cap is a toll-fraud brake, not an invariant, and a transaction here would serialise
    // every login for a marginal off-by-one.
    await this.otp.issue(destination, LOGIN_MFA_PURPOSE, user.id, channel);
    return { destination, channel };
  }

  /**
   * Sends a code to the number on the signed-in user's account, to prove it is theirs.
   *
   * Only ever to the number ALREADY on file — never to one supplied in the request. An
   * endpoint that texts an arbitrary number on an authenticated session is a free SMS
   * gateway for whoever holds the token, and toll fraud is charged by the message.
   * Changing the number is a separate, deliberate operation.
   */
  async sendPhoneVerification(userId: string): Promise<{ sent: true }> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, phone: true, phoneVerifiedAt: true },
    });
    if (!user?.phone) throw new BadRequestException('No phone number on this account.');
    // Idempotent rather than an error: a client that retries after a dropped response
    // should not be told something is wrong when the number is already proved.
    if (user.phoneVerifiedAt) return { sent: true };

    const key = otpDestinationKey(user.phone);
    const now = Date.now();
    const [recent, issuedThisHour] = await Promise.all([
      this.prisma.otpCode.findFirst({
        where: { destination: key, purpose: PHONE_VERIFY_PURPOSE },
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true },
      }),
      this.prisma.otpCode.count({
        where: {
          destination: key,
          purpose: PHONE_VERIFY_PURPOSE,
          createdAt: { gte: new Date(now - LOGIN_MFA_WINDOW_MS) },
        },
      }),
    ]);
    // Same cooldown and hourly cap as the login factor, counted from the OtpCode rows so it
    // survives IP rotation. 429 rather than a silent 200: an endpoint that reports success
    // for a message it did not send teaches the client to start a countdown for a code that
    // will never arrive.
    const cooling = recent != null && now - recent.createdAt.getTime() < loginMfaCooldownMs();
    if (cooling || issuedThisHour >= loginMfaMaxPerWindow()) {
      throw new HttpException('Too many codes requested. Please wait.', HttpStatus.TOO_MANY_REQUESTS);
    }

    await this.otp.issue(user.phone, PHONE_VERIFY_PURPOSE, user.id, 'sms');
    return { sent: true };
  }

  /**
   * Confirms the signup code and stamps phoneVerifiedAt.
   *
   * Until this runs the number is on file but UNPROVEN, which matters because it carries the
   * login second factor, the witness and trustee invitations and the death-claim lookup — a
   * typo stays silent until the will is being executed and nobody can be reached.
   */
  async confirmPhoneVerification(userId: string, code: string): Promise<{ verified: true }> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, phone: true, phoneVerifiedAt: true },
    });
    if (!user?.phone) throw new BadRequestException('No phone number on this account.');
    if (user.phoneVerifiedAt) return { verified: true };

    const ok = await this.otp.verify(user.phone, PHONE_VERIFY_PURPOSE, code);
    if (!ok) throw new BadRequestException('That code is incorrect or has expired.');

    await this.prisma.user.update({ where: { id: user.id }, data: { phoneVerifiedAt: new Date() } });
    return { verified: true };
  }

  private hashChallenge(rawToken: string): string {
    return createHash('sha256').update(rawToken).digest('hex');
  }

  /** 256 random bits; only the SHA-256 hash is stored. Same shape as PasswordResetToken. */
  private async mintLoginChallenge(userId: string): Promise<string> {
    const raw = randomBytes(32).toString('base64url');
    await this.prisma.loginChallenge.create({
      data: {
        userId,
        tokenHash: this.hashChallenge(raw),
        expiresAt: new Date(Date.now() + LOGIN_CHALLENGE_TTL_MS),
      },
    });
    return raw;
  }

  /**
   * Step 1.5 of login: send another code to the SAME place the first one went.
   *
   * The challenge token is the entire authentication. There is no userId in the request, so
   * there is no identifier to probe and nothing to enumerate — an attacker who has not
   * passed the password step cannot cause a single SMS, whoever's user id they hold.
   *
   * Every rejection is ONE status and ONE message. Unknown token, expired token, malformed
   * token, token whose user has since been deleted — all identical, and none of them varies
   * with any account state. Same collapse-everything discipline as resetPasswordWithCode.
   *
   * The response is { sent: true } and nothing else: no destination, no masked contact, no
   * `via`. The client already learned `via` from the login response, so repeating it here
   * would add nothing but a second place for it to leak.
   */
  async resendLoginMfa(rawToken: string): Promise<{ sent: true }> {
    const expired = new UnauthorizedException('Sign-in session expired. Please sign in again.');
    if (typeof rawToken !== 'string' || rawToken.length === 0) throw expired;

    const challenge = await this.prisma.loginChallenge.findUnique({
      where: { tokenHash: this.hashChallenge(rawToken) },
    });
    if (!challenge || challenge.expiresAt < new Date()) throw expired;

    const user = await this.prisma.user.findUnique({ where: { id: challenge.userId } });
    if (!user) throw expired;

    // Resolved by mfaChannel, exactly like validatePassword and verifyMfaAndLogin. Not
    // `user.phone`, and not anything the client supplied — a resend that picked its own
    // destination would reopen the issue/verify mismatch that login MFA and will step-up
    // have each shipped once, and a client-supplied destination would be a free SMS cannon.
    await this.issueLoginMfa(user); // throws 429 before sending if capped or cooling
    return { sent: true };
  }

  /**
   * Where the login code goes: the phone when there is one, otherwise the email.
   *
   * `phone` is OPTIONAL on User, and the old gate required it — so making MFA mandatory
   * without this fallback would have locked every phoneless account out of its own will.
   * Mirrors WillsService.stepUpChannel so issue and verify always key off the same pair.
   */
  private mfaChannel(user: { phone: string | null; email: string; mfaEnabled?: boolean; mfaSecret?: string | null }): {
    destination: string;
    channel: 'sms' | 'email' | 'totp' | 'whatsapp';
  } {
    // An enrolled authenticator OUTRANKS everything, and it is the whole point of having
    // one: nothing is sent, so the login costs nothing to deliver and cannot be
    // intercepted by SIM swap — which NIST SP 800-63B lists SMS as vulnerable to. Saudi
    // SMS alone is the largest third-party line in the product at scale; every account
    // that enrols removes itself from that bill permanently.
    if (user.mfaEnabled && user.mfaSecret) return { destination: '', channel: 'totp' };
    if (!user.phone) return { destination: user.email, channel: 'email' };

    // SAUDI NUMBERS GO OVER WHATSAPP. A Saudi SMS costs $0.1949 — 15.6x a US one and the
    // single most expensive thing this product does per login; the same message over
    // WhatsApp is roughly $0.045. Keyed on the PHONE's country rather than the user's
    // region because the bill follows the destination: a KSA-region user carrying a US
    // number costs US rates, and a Saudi number belonging to a US-region user does not.
    //
    // Restricted to +966 deliberately. WhatsApp is only cheaper where it is also reliably
    // present, and Saudi penetration is near-universal; routing a market where it is not
    // would trade a small saving for undeliverable logins. `whatsappAvailable` keeps this
    // inert until a sender is actually configured, so nothing changes today.
    if (isSaudiPhone(user.phone) && this.otp.whatsappAvailable) {
      return { destination: user.phone, channel: 'whatsapp' };
    }
    return { destination: user.phone, channel: 'sms' };
  }

  async verifyMfaAndLogin(userId: string, code: string, ctx: AuthContext = {}): Promise<AuthSuccess> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException('Invalid session.');

    // Resolved the same way it was issued — not `user.phone`, which would reject every
    // phoneless account at the second step after happily emailing it a code.
    const { destination, channel } = this.mfaChannel(user);
    const primary =
      channel === 'totp'
        ? this.totp.verify(this.totp.open(user.mfaSecret) ?? '', code)
        : await this.otp.verify(destination, LOGIN_MFA_PURPOSE, code).catch(() => false);
    // A backup code is accepted at the SAME step, whatever the primary channel is. That is
    // the entire point of it: the case it exists for is the one where the primary factor
    // cannot be reached at all — a lost authenticator, a dead phone, a number that no
    // longer belongs to you. Tried second so a normal code never touches this path, and
    // consume() is single-use and race-safe.
    //
    // `.catch(() => false)` on the OTP path is load-bearing now: otp.verify THROWS for
    // "no pending code" (which is exactly the state a user in this situation is in), and
    // an exception there would have made the recovery code unreachable.
    const valid = primary || (await this.recoveryCodes.consume(user.id, code));
    // Same message either way. "Invalid or expired" for a TOTP code that is merely wrong
    // is slightly imprecise, but a distinct one would tell an attacker which second factor
    // an account carries, which is a map of who is worth a SIM swap.
    if (!valid) throw new UnauthorizedException('Invalid or expired code.');

    return this.tokens.issueTokenPair(this.toSessionUser(user), ctx);
  }

  /** Called after Google/Apple identity is verified upstream — finds or creates the user. */
  async loginWithOAuth(
    params: {
      email: string;
      providerId: string;
      provider: AuthProvider;
      region?: Region;
      /** The country the user says they live in. Preferred over `region` — see below. */
      addressCountry?: string;
    },
    ctx: AuthContext = {},
  ): Promise<AuthSuccess | MfaChallenge> {
    let user = await this.prisma.user.findUnique({ where: { email: params.email } });
    if (!user) {
      // Residency is DERIVED from the stated country when the client sends one, exactly as
      // register() does — same helper, same server-side decision.
      //
      // This matters more now that OAuth is offered at SIGNUP rather than only to returning
      // users. `region` is the client's own claim; it is bounded by the regions this stack
      // serves, but within that a caller picks their own market — and region is IMMUTABLE
      // and decides pricing, currency and which KYC rail they get. Promoting OAuth to the
      // primary signup path without this would have quietly moved most new accounts onto
      // the weaker of the two derivations.
      //
      // `region` is still honoured when no country is sent, so older clients keep working.
      const region = params.addressCountry
        ? countryToRegion(params.addressCountry)
        : (params.region ?? deploymentRegion());
      this.guardResidency(region);

      user = await this.prisma.user.create({
        data: {
          email: params.email,
          region,
          authProvider: params.provider,
          emailVerified: true, // OAuth providers deliver a verified email address
        },
      });
    }

    // NOT challenged here, unlike the password path.
    //
    // The owner's rule is "a password is never enough on its own; a passkey is". OAuth sits
    // with the passkey: Google and Apple have already run their own strong authentication,
    // and a user with 2FA on their Google account has provided a second factor already.
    // Stacking ours on top is friction that buys little.
    //
    // The former comment here argued the opposite — that OAuth must not let a user bypass
    // a second factor they had deliberately enabled. That reasoning belonged to an OPT-IN
    // MFA world; nothing could ever set mfaEnabled, so it never actually ran. Revisit if a
    // per-user MFA preference is ever introduced.
    return this.tokens.issueTokenPair(this.toSessionUser(user), ctx);
  }

  private toSessionUser(u: { id: string; email: string; region: string; role: string }): SessionUser {
    return { id: u.id, email: u.email, region: u.region, role: u.role };
  }
}
