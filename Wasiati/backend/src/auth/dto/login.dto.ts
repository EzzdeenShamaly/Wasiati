import { IsOptional, IsString, Length } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class LoginDto {
  // Login accepts an email OR a username (e.g. the demo "admin" account), so this
  // is a plain string rather than @IsEmail. Registration stays strict (@IsEmail).
  @IsString()
  email: string;

  @IsString()
  password: string;
}

/**
 * Body for /auth/refresh and /auth/logout. Web clients send the refresh token in
 * an httpOnly cookie (so the body is empty); mobile clients send it here.
 */
export class RefreshDto {
  @ApiPropertyOptional({ description: 'Refresh token (mobile clients only; web uses an httpOnly cookie).' })
  @IsOptional()
  @IsString()
  refreshToken?: string;
}

export class VerifyMfaDto {
  @IsString()
  userId: string;

  @IsString()
  code: string;
}

/**
 * The ENTIRE body of POST /auth/login/resend-mfa.
 *
 * No userId, no destination, no channel, no purpose — on purpose. The token names the user
 * server-side, so the endpoint has no identifier to enumerate, and it cannot be aimed at a
 * phone number or an address of the caller's choosing.
 *
 * This replaces a dormant RequestOtpDto that took `destination` + `purpose` FROM THE CLIENT
 * and was wired to nothing. Had it ever been wired up it would have been an open SMS relay,
 * and a client-chosen destination reintroduces the issue-here/verify-there mismatch that
 * login MFA and will step-up have each shipped once. Deleted rather than left lying around.
 */
export class ResendMfaDto {
  @ApiProperty({ description: 'The opaque challengeToken returned by POST /auth/login.' })
  @IsString()
  challengeToken: string;
}

/** The 6-digit signup code proving the phone on the authenticated user's account. */
export class VerifyPhoneDto {
  @IsString()
  @Length(6, 6)
  code: string;
}
