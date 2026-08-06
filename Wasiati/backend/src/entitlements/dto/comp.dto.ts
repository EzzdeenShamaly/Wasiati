import { IsDateString, IsEnum, IsOptional } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { SubscriptionTier } from '@prisma/client';

export class GrantCompDto {
  @ApiProperty({ enum: SubscriptionTier, description: 'Tier to grant for demo/testing (no payment).' })
  @IsEnum(SubscriptionTier)
  tier: SubscriptionTier;

  @ApiPropertyOptional({ description: 'ISO timestamp when the comp expires; omit for no expiry.' })
  @IsOptional()
  @IsDateString()
  expiresAt?: string;
}
