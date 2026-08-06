import { IsString, IsOptional, IsEmail, MinLength } from 'class-validator';

export class AddTrusteeDto {
  @IsString()
  @MinLength(2)
  fullName: string;

  @IsString()
  phone: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  userId?: string;
}

export class ConfirmTrusteeDto {
  @IsString()
  code: string;
}
