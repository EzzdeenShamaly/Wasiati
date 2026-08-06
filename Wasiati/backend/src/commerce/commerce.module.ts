import { Module } from '@nestjs/common';
import { PricingService } from './pricing.service';
import { PromotionsService } from './promotions.service';
import { OffersService } from './offers.service';
import { CommerceAdminController } from './commerce-admin.controller';
import { CatalogController } from './catalog.controller';

@Module({
  controllers: [CommerceAdminController, CatalogController],
  providers: [PricingService, PromotionsService, OffersService],
  exports: [PricingService, PromotionsService],
})
export class CommerceModule {}
