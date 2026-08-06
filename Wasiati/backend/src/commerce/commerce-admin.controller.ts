import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PricingService } from './pricing.service';
import { PromotionsService } from './promotions.service';
import { OffersService } from './offers.service';
import {
  CreatePricingPlanDto,
  UpdatePricingPlanDto,
  CreatePromotionDto,
  UpdatePromotionDto,
  CreateOfferDto,
  UpdateOfferDto,
} from './dto/commerce.dto';

/**
 * Admin console for the commerce catalog. Everything here lets an admin change
 * pricing, promos, and offers at runtime with NO code change. ADMIN is derived
 * from the JWT (RolesGuard), never trusted from the request body.
 */
@ApiTags('admin-commerce')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/commerce')
export class CommerceAdminController {
  constructor(
    private pricing: PricingService,
    private promotions: PromotionsService,
    private offers: OffersService,
  ) {}

  // --- Pricing plans ---
  @Get('plans')
  @ApiOperation({ summary: 'List all pricing plans (all regions).' })
  listPlans() {
    return this.pricing.listPlans();
  }

  @Post('plans')
  createPlan(@Body() dto: CreatePricingPlanDto, @CurrentUser() admin: { userId: string }) {
    return this.pricing.createPlan(dto, admin.userId);
  }

  @Patch('plans/:id')
  updatePlan(@Param('id') id: string, @Body() dto: UpdatePricingPlanDto, @CurrentUser() admin: { userId: string }) {
    return this.pricing.updatePlan(id, dto, admin.userId);
  }

  @Delete('plans/:id')
  deletePlan(@Param('id') id: string) {
    return this.pricing.deletePlan(id);
  }

  // No price-sync endpoint: we use no provider-side Price objects (Stripe is
  // charged ad-hoc amounts). `PricingPlan.unitAmount` is the price of record and
  // an admin edit takes effect on the next purchase.

  // --- Promotions ---
  @Get('promotions')
  listPromotions() {
    return this.promotions.list();
  }

  @Post('promotions')
  createPromotion(@Body() dto: CreatePromotionDto, @CurrentUser() admin: { userId: string }) {
    return this.promotions.create(dto, admin.userId);
  }

  @Patch('promotions/:id')
  updatePromotion(@Param('id') id: string, @Body() dto: UpdatePromotionDto, @CurrentUser() admin: { userId: string }) {
    return this.promotions.update(id, dto, admin.userId);
  }

  // Archives rather than destroys — a deleted code stays reinstatable and keeps its
  // redemption count. See PromotionsService.archive.
  @Delete('promotions/:id')
  deletePromotion(@Param('id') id: string, @CurrentUser() admin: { userId: string }) {
    return this.promotions.archive(id, admin.userId);
  }

  @Post('promotions/:id/reinstate')
  reinstatePromotion(@Param('id') id: string, @CurrentUser() admin: { userId: string }) {
    return this.promotions.reinstate(id, admin.userId);
  }

  // No coupon-sync endpoint: discounts are applied to the charged amount by
  // PromotionsService.applyToAmount at checkout.

  // --- Offers ---
  @Get('offers')
  listOffers() {
    return this.offers.list();
  }

  @Post('offers')
  createOffer(@Body() dto: CreateOfferDto, @CurrentUser() admin: { userId: string }) {
    return this.offers.create(dto, admin.userId);
  }

  @Patch('offers/:id')
  updateOffer(@Param('id') id: string, @Body() dto: UpdateOfferDto, @CurrentUser() admin: { userId: string }) {
    return this.offers.update(id, dto, admin.userId);
  }

  @Delete('offers/:id')
  deleteOffer(@Param('id') id: string) {
    return this.offers.remove(id);
  }
}
