import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { Request } from 'express';
import { Region } from '@prisma/client';
import { PricingService } from './pricing.service';
import { PromotionsService } from './promotions.service';
import { ValidatePromoDto } from './dto/commerce.dto';
import { resolvePricingRegion } from '../common/geo.util';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';

/**
 * Public commerce endpoints the app reads to render pricing dynamically. No auth
 * REQUIRED — this is the storefront catalog, and a signed-out visitor must be able
 * to see prices. It reflects admin edits instantly.
 *
 * But auth is READ when present (OptionalJwtAuthGuard): a member's currency comes
 * from their account, never from where they are browsing from. See
 * `resolvePricingRegion`.
 */
@ApiTags('catalog')
@Controller('pricing')
export class CatalogController {
  constructor(
    private pricing: PricingService,
    private promotions: PromotionsService,
  ) {}

  /**
   * The region/currency a caller is priced in — the ONE rule, applied identically
   * by the catalog and the promo preview below (and by checkout, in PaymentsService).
   *
   * Signed in → the account region, and nothing the client says can move it.
   * Anonymous → ?region= / geo-IP.
   */
  private async regionFor(req: Request, user: { userId?: string } | undefined, explicitRegion?: string) {
    const accountRegion = user?.userId ? await this.pricing.accountRegion(user.userId) : null;
    return resolvePricingRegion({ accountRegion, explicitRegion, req });
  }

  @Get()
  @UseGuards(OptionalJwtAuthGuard)
  @ApiOperation({
    summary: 'Active pricing plans + live offers, priced for the caller.',
    description:
      "SIGNED IN: region/currency is the user's ACCOUNT region — ?region= and geo headers are ignored, " +
      'so a member on a VPN (or one editing the query string) still sees their own currency. ' +
      "ANONYMOUS: an explicit ?region= wins, otherwise Cloudflare's CF-IPCountry header " +
      '(US->USD, CA->CAD, Saudi Arabia->SAR, Qatar->QAR, everywhere else->USD).',
  })
  @ApiQuery({ name: 'region', enum: Region, required: false, description: 'Anonymous visitors only; ignored when signed in.' })
  async catalog(
    @Req() req: Request,
    @CurrentUser() user: { userId: string } | undefined,
    @Query('region') region?: string,
  ) {
    return this.pricing.getCatalog(await this.regionFor(req, user, region));
  }

  @Post('validate-promo')
  @UseGuards(OptionalJwtAuthGuard)
  @ApiOperation({
    summary: 'Preview whether a promo code is valid for a tier/region.',
    description:
      "Same region rule as the catalog: a signed-in user is previewed against their ACCOUNT region, so the " +
      'preview cannot disagree with what checkout will actually do. `region` in the body is for anonymous visitors.',
  })
  async validatePromo(
    @Req() req: Request,
    @CurrentUser() user: { userId: string } | undefined,
    @Body() dto: ValidatePromoDto,
  ) {
    // A region-restricted code must preview against the region we will really
    // charge — otherwise a signed-in member is told a code works and checkout
    // then silently drops it. Same reasoning for the userId: a returning customer
    // previewing a first-subscription-only code should be told now, not at checkout.
    // Anonymous visitors preview optimistically (see validate); the money path enforces.
    return this.promotions.validate(
      dto.code,
      dto.tier,
      await this.regionFor(req, user, dto.region),
      user?.userId,
    );
  }
}
