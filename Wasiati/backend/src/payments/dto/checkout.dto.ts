import { IsEnum, IsOptional, IsString, IsUrl } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PriceInterval, SubscriptionTier } from '@prisma/client';

export class CreateCheckoutDto {
  @ApiProperty({ enum: SubscriptionTier }) @IsEnum(SubscriptionTier) tier: SubscriptionTier;
  // NO `region` field, deliberately. Checkout is always authenticated, so the region
  // (and therefore the currency and the price) comes from the buyer's ACCOUNT — never
  // from the client. A client that still sends one is silently stripped by the global
  // ValidationPipe's `whitelist: true`, which is exactly the intent.
  /** Required once a tier offers both monthly and annual plans — otherwise the
   *  lookup is ambiguous and could charge the wrong price. */
  @ApiPropertyOptional({ enum: PriceInterval })
  @IsOptional()
  @IsEnum(PriceInterval)
  interval?: PriceInterval;
  @ApiPropertyOptional() @IsOptional() @IsString() promoCode?: string;
  @ApiProperty() @IsUrl({ require_tld: false }) successUrl: string;
  @ApiProperty() @IsUrl({ require_tld: false }) cancelUrl: string;
}

export class CreatePortalDto {
  @ApiProperty() @IsUrl({ require_tld: false }) returnUrl: string;
}

/** Where the hosted "change card" page returns the customer to. Same open-redirect
 *  constraint as checkout (PAYMENT_RETURN_HOSTS). */
export class ChangePaymentMethodDto {
  @ApiProperty() @IsUrl({ require_tld: false }) successUrl: string;
  @ApiProperty() @IsUrl({ require_tld: false }) cancelUrl: string;
}
