import { IsBoolean, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

/**
 * Relation keys the heir registry offers (create-flow step 2). These are the
 * human-roster relations from the prototype's relOptions — NOT the fara'id
 * HeirRelation enum (which drives ShariaShare). A registry row is "who to reach",
 * not "who inherits what".
 */
export const HEIR_CONTACT_RELATIONS = [
  'wife',
  'husband',
  'son',
  'daughter',
  'mother',
  'father',
  'brother',
  'sister',
  'other',
] as const;

export type HeirContactRelation = (typeof HEIR_CONTACT_RELATIONS)[number];

/**
 * A heir-registry row. Rows are saved as the owner builds them, so every field
 * except the relation is permissive: name/phone/email may be blank mid-entry and
 * are completed before sealing (the UI gates the seal on completeness). No strict
 * email-format check at write time — an incomplete draft row must still persist.
 */
export class CreateHeirContactDto {
  @IsIn(HEIR_CONTACT_RELATIONS as unknown as string[])
  relation: string;

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

  @IsOptional()
  @IsBoolean()
  isMinor?: boolean;
}

export class UpdateHeirContactDto {
  @IsOptional()
  @IsIn(HEIR_CONTACT_RELATIONS as unknown as string[])
  relation?: string;

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

  @IsOptional()
  @IsBoolean()
  isMinor?: boolean;
}
