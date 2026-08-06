import { IsString, IsOptional, IsEmail, MinLength } from 'class-validator';

export class AddWitnessDto {
  @IsString()
  @MinLength(2)
  fullName: string;

  @IsString()
  phone: string;

  // Optional but recommended: where posthumous download/deletion reminders are sent.
  @IsOptional()
  @IsEmail()
  email?: string;
}

export class ConfirmWitnessDto {
  @IsString()
  code: string;

  @IsString()
  signatureData: string;

  // The witness's legal name as on their ID — must match the name on the will
  // before the signature is recorded (spec §6, "national-ID name match").
  @IsString()
  @MinLength(2)
  legalName: string;
}
