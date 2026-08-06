import { IsEmail, IsEnum, IsISO31661Alpha2, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { Region } from '@prisma/client';

/**
 * Page 1 of signup: who you are and how we reach you.
 *
 * Phone is REQUIRED here, where it used to be optional. It is not a marketing field — it
 * carries the login second factor, the witness and trustee invitations, and the death-claim
 * lookup. A will whose owner left it blank is one whose executors cannot be reached at the
 * moment it matters. It is proved by OTP immediately after this call.
 *
 * The address is structured rather than one free-text line because it does real work: it
 * decides jurisdiction (which fara'id wording and which legal notices the will carries) and
 * it is printed into the executed document. Neither survives "123 Some St, somewhere".
 *
 * Which address fields are REQUIRED is country-dependent and enforced in the service against
 * per-country rules, not here: postal codes are mandatory in the US and Canada, unused in
 * Qatar, and optional in Saudi Arabia, so a blanket rule here would reject perfectly valid
 * addresses in half the markets we sell in.
 */
export class RegisterDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(10)
  password: string;

  @IsEnum(Region)
  region: Region;

  @IsString()
  @MinLength(6)
  @MaxLength(24)
  phone: string;

  @IsString()
  @MaxLength(200)
  addressLine1: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  addressLine2?: string;

  @IsString()
  @MaxLength(100)
  addressCity: string;

  /** State / province / emirate — whatever the country calls its administrative area. */
  @IsOptional()
  @IsString()
  @MaxLength(100)
  addressArea?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  addressPostalCode?: string;

  /**
   * ISO 3166-1 alpha-2. Deliberately NOT the Region enum — Region is the four markets we
   * sell in, and a customer in one of them may live somewhere else entirely.
   */
  @IsISO31661Alpha2()
  addressCountry: string;
}
