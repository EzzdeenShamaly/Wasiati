import { IsEnum, IsArray, IsObject, ValidateNested, IsString, IsNumber, IsOptional, IsIn, Min, Max, MinLength, MaxLength, Equals } from 'class-validator';
import { Type } from 'class-transformer';
import { Madhhab } from '../sharia-calculator';

export const HEIR_RELATIONS = [
  'HUSBAND',
  'WIFE',
  'SON',
  'DAUGHTER',
  'SON_SON',
  'SON_DAUGHTER',
  'FATHER',
  'MOTHER',
  'GRANDFATHER',
  'PATERNAL_GRANDMOTHER',
  'MATERNAL_GRANDMOTHER',
  'GRANDMOTHER',
  'FULL_BROTHER',
  'FULL_SISTER',
  'CONSANGUINE_BROTHER',
  'CONSANGUINE_SISTER',
  'MATERNAL_SIBLING',
  'FULL_NEPHEW',
  'CONSANGUINE_NEPHEW',
  'FULL_UNCLE',
  'CONSANGUINE_UNCLE',
  'FULL_COUSIN',
  'CONSANGUINE_COUSIN',
] as const;

export class HeirDto {
  @IsEnum(HEIR_RELATIONS)
  relation: (typeof HEIR_RELATIONS)[number];

  @IsString()
  name: string;
}

export class CreateWillDto {
  @IsEnum(['BASIC', 'STANDARD', 'PREMIUM', 'ULTIMATE'])
  tier: 'BASIC' | 'STANDARD' | 'PREMIUM' | 'ULTIMATE';

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => HeirDto)
  heirs: HeirDto[];

  // School of jurisprudence. Governs radd (Mālikī/Shāfiʿī send a surplus to bayt
  // al-māl instead of returning it to the sharers) and the disputed
  // grandfather-with-siblings case (Ḥanafī: the grandfather blocks them).
  // Defaults to the majority view (JUMHUR) if omitted.
  @IsOptional()
  @IsEnum(['JUMHUR', 'HANAFI', 'MALIKI', 'SHAFII', 'HANBALI'])
  madhhab?: Madhhab;

  // Must be explicitly true — the frontend should require a checkbox showing
  // DISCLAIMER_TEXT before this can be submitted. No silent default.
  @Equals(true, { message: 'You must accept the legal disclaimer before creating a will.' })
  disclaimerAccepted: boolean;
}

export class SignWillDto {
  // Captured signature (base64 image or vector path). Stored encrypted at rest.
  @IsString()
  @MinLength(1)
  signatureData: string;
}

export class AddBequestDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  beneficiaryName: string;

  @IsNumber()
  @Min(0)
  @Max(100)
  sharePercent: number;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;
}

export class UpdateWillMessageDto {
  // The private "words for my family" letter. Plain text; the service sanitises
  // it (strips markup/code) before persisting, and caps the length.
  @IsString()
  @MaxLength(8000) // generous pre-sanitise cap; the service trims to 5000 clean chars
  personalMessage: string;
}

/**
 * Create-flow autosave (spec §3 autosave / acceptance #5). The client sends its
 * whole form snapshot ≤1s after each change; the service stores it opaquely on
 * the DRAFT will and lifts the parts that belong to the will itself (heirs →
 * recomputed shares, wishes → funeralWishes, words → personalMessage, bequest →
 * its own Bequest row). Size-capped in the service.
 */
export class UpdateWillDraftDto {
  @IsObject()
  draftState: Record<string, unknown>;
}

/**
 * Guardianship of minor children (create-flow step 3). `mode` is 'parent'
 * (surviving parent — the default), 'islamic' (the sharia order of guardianship),
 * or 'named' (a named guardian, whose contact details ride the optional fields).
 * The name/phone/email are only meaningful for 'named' but are accepted (blank)
 * for the other modes so switching modes never 400s a partially-filled form.
 */
export class UpdateGuardianDto {
  @IsIn(['parent', 'islamic', 'named'])
  mode: 'parent' | 'islamic' | 'named';

  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  email?: string;
}

/**
 * Step-up re-authentication (spec §3): delete and unpublish must present the SMS
 * one-time code issued by POST /wills/:willId/step-up-otp.
 */
export class WillStepUpDto {
  @IsString()
  @MinLength(4)
  @MaxLength(10)
  otp: string;
}
