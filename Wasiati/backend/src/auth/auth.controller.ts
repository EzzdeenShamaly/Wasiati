import { Body, Controller, Get, Post, Req, Res, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Throttle } from '@nestjs/throttler';
import { Request, Response } from 'express';
import { AuthService, AuthSuccess, MfaChallenge } from './auth.service';
import { GoogleAuthService } from './strategies/google-auth.service';
import { AppleAuthService } from './strategies/apple-auth.service';
import { MicrosoftAuthService } from './strategies/microsoft-auth.service';
import { TokenService, AuthContext } from './token.service';
import { AuthCookieService } from './auth-cookie.service';
import { AccountRecoveryService } from './account-recovery.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto, VerifyMfaDto, RefreshDto, ResendMfaDto, VerifyPhoneDto } from './dto/login.dto';
import {
  VerifyEmailDto,
  ResendVerificationDto,
  ForgotPasswordDto,
  ResetPasswordDto,
  ResetPasswordWithCodeDto,
} from './dto/recovery.dto';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private authService: AuthService,
    private googleAuth: GoogleAuthService,
    private appleAuth: AppleAuthService,
    private microsoftAuth: MicrosoftAuthService,
    private tokens: TokenService,
    private cookies: AuthCookieService,
    private recovery: AccountRecoveryService,
  ) {}

  @Throttle({ default: { limit: 5, ttl: 60000 } }) // limit signup spam
  @Post('register')
  async register(@Body() dto: RegisterDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.deliver(await this.authService.register(dto, this.ctx(req)), req, res);
  }

  @Throttle({ default: { limit: 8, ttl: 60000 } }) // brute-force protection on password login
  @Post('login')
  async login(@Body() dto: LoginDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.deliver(await this.authService.validatePassword(dto, this.ctx(req)), req, res);
  }

  @Throttle({ default: { limit: 10, ttl: 60000 } }) // limit OTP guessing
  @Post('login/verify-mfa')
  async verifyMfa(@Body() dto: VerifyMfaDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return this.deliver(await this.authService.verifyMfaAndLogin(dto.userId, dto.code, this.ctx(req)), req, res);
  }

  /**
   * Send another login code, for the user whose code never arrived or has expired.
   *
   * Authenticated SOLELY by the opaque challengeToken minted at the password step. The body
   * carries no user identifier at all, which is the property that makes this endpoint
   * non-enumerable: there is nothing in the request to vary. An unauthenticated caller —
   * including one holding a leaked userId, which is not a credential and appears in login
   * responses, logs and support screenshots — cannot trigger a single SMS.
   *
   * NOT @UseGuards(JwtAuthGuard): there is no session yet, that is the entire point.
   *
   * Three limits stack, all before any send: this per-IP throttle (3/min, matching
   * resend-verification), then the per-destination 30s cooldown and 5/hour cap inside
   * AuthService.issueLoginMfa — which survive IP rotation because they count OtpCode rows
   * rather than requests.
   */
  @Throttle({ default: { limit: 3, ttl: 60000 } }) // limit SMS bombing per IP
  @Post('login/resend-mfa')
  @ApiOperation({
    summary: 'Re-send the login MFA code using the challenge token from POST /auth/login.',
  })
  resendMfa(@Body() dto: ResendMfaDto) {
    // Returns { sent: true } and nothing else — no destination, no masked contact, no via.
    // In dev, OTP_DEV_ECHO makes the code readable at GET /dev/sms; it is never echoed here.
    return this.authService.resendLoginMfa(dto.challengeToken);
  }

  /** Client obtains a Google id_token via the SDK; we verify it server-side (never
   *  trust a client-supplied email — the token's signature is the source of truth). */
  @Post('login/google')
  async loginWithGoogle(
    @Body() body: { idToken: string; region?: 'KSA' | 'CA' | 'US'; addressCountry?: string },
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const verified = await this.googleAuth.verifyIdToken(body.idToken);
    const result = await this.authService.loginWithOAuth(
      { email: verified.email, providerId: verified.providerId, provider: 'GOOGLE' as any, region: body.region, addressCountry: body.addressCountry },
      this.ctx(req),
    );
    return this.deliver(result, req, res);
  }

  /** Client hands us Apple's identityToken (Sign in with Apple); we verify server-side. */
  @Post('login/apple')
  async loginWithApple(
    @Body() body: { identityToken: string; region?: 'KSA' | 'CA' | 'US'; addressCountry?: string },
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const verified = await this.appleAuth.verifyIdentityToken(body.identityToken);
    const result = await this.authService.loginWithOAuth(
      { email: verified.email, providerId: verified.providerId, provider: 'APPLE' as any, region: body.region, addressCountry: body.addressCountry },
      this.ctx(req),
    );
    return this.deliver(result, req, res);
  }

  /** Client hands us Microsoft's id_token (Entra ID / MSAL); we verify server-side. */
  @Post('login/microsoft')
  async loginWithMicrosoft(
    @Body() body: { idToken: string; region?: 'KSA' | 'CA' | 'US'; addressCountry?: string },
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ) {
    const verified = await this.microsoftAuth.verifyIdToken(body.idToken);
    const result = await this.authService.loginWithOAuth(
      { email: verified.email, providerId: verified.providerId, provider: 'MICROSOFT' as any, region: body.region, addressCountry: body.addressCountry },
      this.ctx(req),
    );
    return this.deliver(result, req, res);
  }

  @Post('refresh')
  @ApiOperation({ summary: 'Rotate the refresh token and mint a new access token.' })
  async refresh(@Body() body: RefreshDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    const presented = this.cookies.readRefreshToken(req, body?.refreshToken);
    if (!presented) throw new UnauthorizedException('No refresh token provided.');
    const rotated = await this.tokens.rotateRefreshToken(presented, this.ctx(req));
    return this.cookies.deliver(req, res, rotated);
  }

  @Post('logout')
  @ApiOperation({ summary: 'Revoke the current refresh-token family and clear the cookie.' })
  async logout(@Body() body: RefreshDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    const presented = this.cookies.readRefreshToken(req, body?.refreshToken);
    if (presented) await this.tokens.revokeByToken(presented);
    this.cookies.clearRefreshCookie(res);
    return { success: true };
  }

  // --- email verification & password reset ---------------------------------

  @Throttle({ default: { limit: 6, ttl: 60000 } }) // token-consuming — limit guessing
  @Post('verify-email')
  @ApiOperation({ summary: 'Confirm an email address from the emailed token.' })
  verifyEmail(@Body() dto: VerifyEmailDto) {
    return this.recovery.verifyEmail(dto.token);
  }

  @Throttle({ default: { limit: 3, ttl: 60000 } }) // limit verification-email bombing
  @Post('resend-verification')
  @ApiOperation({ summary: 'Resend the verification email (always 200 — no account disclosure).' })
  async resendVerification(@Body() dto: ResendVerificationDto) {
    await this.recovery.resendVerification(dto.email);
    return { success: true };
  }

  @Throttle({ default: { limit: 4, ttl: 60000 } }) // limit reset-email bombing
  @Post('password/forgot')
  @ApiOperation({ summary: 'Request a password-reset email (always 200 — no account disclosure).' })
  async forgotPassword(@Body() dto: ForgotPasswordDto) {
    await this.recovery.requestPasswordReset(dto.email);
    return { success: true };
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } }) // token-consuming — limit guessing
  @Post('password/reset')
  @ApiOperation({ summary: 'Reset the password from the emailed token; revokes all sessions.' })
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.recovery.resetPassword(dto.token, dto.newPassword);
  }

  // --- reset by one-time CODE (the preferred path) --------------------------
  //
  // The emailed token above is a bearer credential: whoever holds that mail — a forwarded
  // thread, a shared family inbox, a synced device — can take the account. A will platform
  // has more shared inboxes than most products. A code has to be typed into the session
  // that asked for it, and when the user has a phone it moves the reset onto a SECOND
  // channel, so owning the mailbox alone is no longer enough. Same posture as login
  // (f242634): a password is never sufficient on its own.
  //
  // The link flow stays for now so any mail already in someone's inbox keeps working.

  @Throttle({ default: { limit: 4, ttl: 60000 } }) // limit code bombing
  @Post('password/forgot-code')
  @ApiOperation({
    summary: 'Send a one-time reset code by SMS (or email when there is no phone). Always 200.',
  })
  async forgotPasswordCode(@Body() dto: ForgotPasswordDto) {
    return this.recovery.requestPasswordResetCode(dto.email);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } }) // code-consuming — limit guessing
  @Post('password/reset-code')
  @ApiOperation({ summary: 'Reset the password from a one-time code; revokes all sessions.' })
  resetPasswordWithCode(@Body() dto: ResetPasswordWithCodeDto) {
    return this.recovery.resetPasswordWithCode(dto.email, dto.code, dto.newPassword);
  }

  /**
   * Step 2 of signup: prove the number given on step 1.
   *
   * AUTHENTICATED, unlike the rest of this controller — registration already signed the user
   * in, so the session identifies whose number to text. Nothing in the body names a
   * destination: the code only ever goes to the number already on the account. An endpoint
   * that texts an arbitrary number on a valid session is a free SMS gateway, and toll fraud
   * is charged per message.
   */
  // --- authenticator app (TOTP) --------------------------------------------
  //
  // The free second factor, and the one that removes an account from the SMS bill for
  // good. Enrolment is two steps on purpose: a secret that was shown but never actually
  // scanned would otherwise lock the owner behind a code they cannot produce.

  // --- recovery codes -------------------------------------------------------
  //
  // The escape hatch that makes an authenticator safe to rely on. Accepted at the normal
  // MFA step, so a user who has lost their device does not need a separate flow — or a
  // support human willing to take their word for who they are.

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('mfa/recovery-codes')
  @ApiOperation({ summary: 'How many backup codes remain on this account.' })
  recoveryCodesStatus(@CurrentUser() user: { userId: string }) {
    return this.authService.recoveryCodesStatus(user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 3, ttl: 60000 } })
  @Post('mfa/recovery-codes')
  @ApiOperation({ summary: 'Issue a fresh set of backup codes. Invalidates the previous set. Shown once.' })
  regenerateRecoveryCodes(@CurrentUser() user: { userId: string }) {
    return this.authService.regenerateRecoveryCodes(user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Get('mfa/totp')
  @ApiOperation({ summary: 'Whether an authenticator app is set up on this account.' })
  totpStatus(@CurrentUser() user: { userId: string }) {
    return this.authService.totpStatus(user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('mfa/totp/start')
  @ApiOperation({ summary: 'Begin enrolment: returns a secret + otpauth:// URI to scan. Enables nothing.' })
  startTotp(@CurrentUser() user: { userId: string }) {
    return this.authService.startTotpEnrollment(user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60000 } }) // code-consuming — limit guessing
  @Post('mfa/totp/enable')
  @ApiOperation({ summary: 'Confirm a code from the app and switch the authenticator on.' })
  enableTotp(@CurrentUser() user: { userId: string }, @Body() body: { secret: string; code: string }) {
    return this.authService.enableTotp(user.userId, body?.secret, body?.code);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('mfa/totp/disable')
  @ApiOperation({ summary: 'Turn the authenticator off. Requires a current code.' })
  disableTotp(@CurrentUser() user: { userId: string }, @Body() body: { code: string }) {
    return this.authService.disableTotp(user.userId, body?.code);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('phone/send-code')
  @ApiOperation({ summary: 'Send a verification code to the phone on this account.' })
  sendPhoneCode(@CurrentUser() user: { userId: string }) {
    return this.authService.sendPhoneVerification(user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @Throttle({ default: { limit: 5, ttl: 60000 } }) // code-consuming — limit guessing
  @Post('phone/verify')
  @ApiOperation({ summary: 'Confirm the code and mark this phone verified.' })
  verifyPhone(@CurrentUser() user: { userId: string }, @Body() dto: VerifyPhoneDto) {
    return this.authService.confirmPhoneVerification(user.userId, dto.code);
  }

  // --- helpers -------------------------------------------------------------

  private ctx(req: Request): AuthContext {
    return { userAgent: req.headers['user-agent'], ipAddress: req.ip };
  }

  /** MFA challenge passes straight through; success is shaped by AuthCookieService. */
  private deliver(result: AuthSuccess | MfaChallenge, req: Request, res: Response) {
    if ('mfaRequired' in result) return result;
    return this.cookies.deliver(req, res, result);
  }
}
