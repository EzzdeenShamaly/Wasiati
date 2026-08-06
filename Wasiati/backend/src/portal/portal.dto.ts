import { ClaimRole } from '@prisma/client';
import { IsEmail, IsIn, IsString, Length } from 'class-validator';

/**
 * The two roles that may hold a portal session. WITNESS is deliberately absent: a witness
 * attests to the SIGNING of the will, they are not a beneficiary of it and have nothing to
 * read here. `ClaimRole.WITNESS` therefore never reaches a PORTAL_READ token.
 */
export const PORTAL_ROLES = [ClaimRole.HEIR, ClaimRole.TRUSTEE] as const;
export type PortalRole = (typeof PORTAL_ROLES)[number];

export class PortalStartDto {
  @IsIn(PORTAL_ROLES as unknown as string[])
  role: PortalRole;

  @IsEmail()
  @Length(3, 320)
  email: string;
}

export class PortalVerifyDto {
  @IsIn(PORTAL_ROLES as unknown as string[])
  role: PortalRole;

  @IsEmail()
  @Length(3, 320)
  email: string;

  // Length only — never a numeric/format constraint that would answer "was that even a
  // code?" differently from "was that the RIGHT code?". Every wrong input must come back
  // through the one uniform error in PortalService.verify.
  @IsString()
  @Length(4, 12)
  code: string;
}
