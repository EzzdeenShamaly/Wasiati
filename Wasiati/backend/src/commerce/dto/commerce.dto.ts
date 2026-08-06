import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsEnum,
  IsInt,
  IsISO8601,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional, OmitType, PartialType } from '@nestjs/swagger';
import { PriceInterval, PromotionType, Region, SubscriptionTier } from '@prisma/client';

export class CreatePricingPlanDto {
  @ApiProperty({ enum: SubscriptionTier }) @IsEnum(SubscriptionTier) tier: SubscriptionTier;
  @ApiProperty({ enum: Region }) @IsEnum(Region) region: Region;
  @ApiProperty({ example: 'USD' }) @IsString() @Length(3, 3) currency: string;
  @ApiProperty({ description: 'Minor units (cents/halalas)', example: 999 }) @IsInt() @Min(0) unitAmount: number;
  @ApiPropertyOptional({ enum: PriceInterval }) @IsOptional() @IsEnum(PriceInterval) interval?: PriceInterval;
  @ApiProperty() @IsString() @MaxLength(120) displayName: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) description?: string;
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({ each: true }) @MaxLength(200, { each: true }) features?: string[];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) badge?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() sortOrder?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}

export class UpdatePricingPlanDto extends PartialType(CreatePricingPlanDto) {}

export class CreatePromotionDto {
  @ApiProperty({ example: 'LAUNCH25' }) @IsString() @MaxLength(40) code: string;
  @ApiProperty({ enum: PromotionType }) @IsEnum(PromotionType) type: PromotionType;
  @ApiProperty({ description: 'Percent (1-100) or minor-unit amount', example: 25 }) @IsInt() @Min(1) @Max(100_000_000) value: number;
  @ApiPropertyOptional({ description: 'Required for AMOUNT type' }) @IsOptional() @IsString() @Length(3, 3) currency?: string;
  @ApiPropertyOptional({ enum: SubscriptionTier, isArray: true }) @IsOptional() @IsArray() @ArrayMaxSize(8) @IsEnum(SubscriptionTier, { each: true }) appliesToTiers?: SubscriptionTier[];
  @ApiPropertyOptional({ enum: Region, isArray: true }) @IsOptional() @IsArray() @ArrayMaxSize(8) @IsEnum(Region, { each: true }) appliesToRegions?: Region[];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(1_000_000) maxRedemptions?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() firstTimeOnly?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsISO8601() startsAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsISO8601() endsAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}

/**
 * PATCH body. The three limit fields are re-declared as nullable because a PATCH must
 * distinguish "leave unchanged" (absent) from "clear it" (explicit null): an admin has
 * to be able to REMOVE a cap or a date window, not only set one. @IsOptional() skips
 * the inner validators for null exactly as it does for undefined, so null passes.
 */
export class UpdatePromotionDto extends PartialType(
  OmitType(CreatePromotionDto, ['maxRedemptions', 'startsAt', 'endsAt'] as const),
) {
  @ApiPropertyOptional({ nullable: true, description: 'null removes the redemption cap' })
  @IsOptional() @IsInt() @Min(1) @Max(1_000_000) maxRedemptions?: number | null;
  @ApiPropertyOptional({ nullable: true, description: 'null makes the code start immediately' })
  @IsOptional() @IsISO8601() startsAt?: string | null;
  @ApiPropertyOptional({ nullable: true, description: 'null removes the expiry' })
  @IsOptional() @IsISO8601() endsAt?: string | null;
}

export class CreateOfferDto {
  @ApiProperty() @IsString() @MaxLength(120) title: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) subtitle?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) body?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) badge?: string;
  @ApiPropertyOptional({ enum: Region }) @IsOptional() @IsEnum(Region) region?: Region;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(64) promotionId?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(60) ctaLabel?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() sortOrder?: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsISO8601() startsAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsISO8601() endsAt?: string;
}

export class UpdateOfferDto extends PartialType(CreateOfferDto) {}

export class ValidatePromoDto {
  @ApiProperty() @IsString() code: string;
  @ApiPropertyOptional({ enum: SubscriptionTier }) @IsOptional() @IsEnum(SubscriptionTier) tier?: SubscriptionTier;
  @ApiPropertyOptional({ enum: Region }) @IsOptional() @IsEnum(Region) region?: Region;
}
