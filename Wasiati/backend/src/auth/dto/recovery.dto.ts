import { IsEmail, IsString, Length, MinLength } from 'class-validator';

export class VerifyEmailDto {
  @IsString()
  token: string;
}

export class ResendVerificationDto {
  @IsEmail()
  email: string;
}

export class ForgotPasswordDto {
  @IsEmail()
  email: string;
}

export class ResetPasswordDto {
  @IsString()
  token: string;

  @IsString()
  @MinLength(10)
  newPassword: string;
}

/**
 * Reset by one-time code rather than an emailed link.
 *
 * `email` identifies the account; the CODE is the proof — sent to the phone when there is
 * one, else the email. Carrying the address here (instead of a server-side session) keeps
 * the endpoint stateless and lets the verify step resolve the same destination the code was
 * issued to. Every failure answers identically, so this cannot become an existence oracle.
 */
export class ResetPasswordWithCodeDto {
  @IsEmail()
  email: string;

  @IsString()
  @Length(6, 6)
  code: string;

  @IsString()
  @MinLength(10)
  newPassword: string;
}
