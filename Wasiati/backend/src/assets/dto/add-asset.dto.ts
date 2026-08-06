import { IsEnum, IsString, IsOptional, IsNumber, Min, MaxLength } from 'class-validator';
import { AssetType } from '@prisma/client';

export class AddAssetDto {
  @IsEnum(AssetType)
  type: AssetType;

  @IsString()
  @MaxLength(200)
  label: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  institution?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  estimatedValue?: number;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  currency?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  notes?: string;

  // Contact + reference so heirs know where the asset is and who to call
  // (prototype 9a). The reference is masked in the UI; stored in full.
  @IsOptional()
  @IsString()
  @MaxLength(40)
  contactPhone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  contactEmail?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  accountRef?: string;
}
