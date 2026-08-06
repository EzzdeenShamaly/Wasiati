import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PriceInterval, Region, SubscriptionTier } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreatePricingPlanDto, UpdatePricingPlanDto } from './dto/commerce.dto';
import { REGION_CURRENCY } from '../common/geo.util';
import { isPurchasable } from './plan-rules';

/** Badge text applied to the data-driven most-popular plan. */
const MOST_POPULAR_BADGE = 'Most popular';

/**
 * Admin-managed pricing catalog. Prices are edited at runtime (no code changes).
 *
 * There is no provider-side price object to sync: Stripe is charged an amount
 * per transaction (ad-hoc price_data, no Price objects), so `unitAmount` in this
 * table IS the price of record. That removes the immutable-Price sync dance
 * Stripe Billing would require.
 */
@Injectable()
export class PricingService {
  private readonly logger = new Logger(PricingService.name);

  constructor(private prisma: PrismaService) {}

  listPlans() {
    return this.prisma.pricingPlan.findMany({ orderBy: [{ region: 'asc' }, { sortOrder: 'asc' }] });
  }

  /**
   * The signed-in user's ACCOUNT region — the authority for which market they are
   * priced in (see resolvePricingRegion). Read from the row rather than trusted
   * from the JWT's `region` claim: the account is the record, and a token minted
   * before an admin corrected someone's region would otherwise keep pricing them
   * in the wrong currency until it expired.
   *
   * Null when the id resolves to nothing, so the caller degrades to geo rather
   * than failing the storefront.
   */
  async accountRegion(userId: string): Promise<Region | null> {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { region: true } });
    return user?.region ?? null;
  }

  /**
   * The tier people actually subscribe to the most — for the data-driven "Most popular"
   * badge. Counts only RECURRING (monthly/yearly) ACTIVE subscriptions — one-time Basic
   * purchases now also create an ACTIVE subscription (for entitlement), so they must be
   * excluded here: the "Most popular" badge is for the subscription tiers, and if Basic
   * (one-time) won the count it would be dropped by the interval guard in getCatalog,
   * blanking the badge entirely. Returns null when there's no recurring data yet, so the
   * caller falls back to the seeded default badge instead of showing nothing at launch.
   */
  private async mostPopularTier(): Promise<SubscriptionTier | null> {
    const grouped = await this.prisma.subscription.groupBy({
      by: ['tier'],
      // DB is already region-scoped (data residency); count recurring subs only.
      where: { status: 'ACTIVE', interval: { in: [PriceInterval.MONTH, PriceInterval.YEAR] } },
      _count: { _all: true },
    });
    if (grouped.length === 0) return null;
    grouped.sort((a, b) => b._count._all - a._count._all);
    return grouped[0].tier;
  }

  /** Public, region-scoped catalog for the app: active plans + live offers. */
  async getCatalog(region: Region) {
    const now = new Date();
    const [rawPlans, rawOffers, popularTier] = await Promise.all([
      this.prisma.pricingPlan.findMany({ where: { region, active: true }, orderBy: { sortOrder: 'asc' } }),
      this.prisma.offer.findMany({
        where: {
          active: true,
          AND: [
            { OR: [{ region }, { region: null }] },
            { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
            { OR: [{ endsAt: null }, { endsAt: { gte: now } }] },
          ],
        },
        orderBy: { sortOrder: 'asc' },
      }),
      this.mostPopularTier(),
    ]);

    // Data-driven "Most popular": badge the tier people actually subscribe to most.
    // Before there's any subscription data (popularTier === null), keep whatever badge
    // was seeded (Premium by default) so the storefront isn't badge-less at launch.
    //
    // `purchasable` carries the (tier, interval) product rule (plan-rules.ts) to the
    // app so it can hide what cannot be sold — e.g. Ultimate on the one-time cycle.
    // It is computed here rather than filtered away so the app can still tell that
    // the tier EXISTS in this region and explain why it is absent from this cycle.
    // PUBLIC shape. `GET /pricing` is unauthenticated (OptionalJwtAuthGuard) and is now
    // read by the marketing site as well as the app, so return ONLY what a storefront
    // needs. The provider ids, the last editor and the row timestamps are internal and
    // must never reach an anonymous caller — admins read whole rows from
    // `GET /admin/commerce/plans` (listPlans), which is unaffected by this projection.
    const plans = rawPlans.map((p) => {
      const purchasable = isPurchasable(p.tier, p.interval);
      const isPopular = p.tier === popularTier && p.interval !== PriceInterval.ONE_TIME;
      return {
        id: p.id,
        tier: p.tier,
        region: p.region,
        currency: p.currency,
        unitAmount: p.unitAmount,
        interval: p.interval,
        displayName: p.displayName,
        description: p.description,
        features: p.features,
        // popularTier === null (no recurring data yet) → keep the seeded badge.
        badge: popularTier === null ? p.badge : isPopular ? MOST_POPULAR_BADGE : null,
        sortOrder: p.sortOrder,
        active: p.active,
        purchasable,
      };
    });

    // Resolve each offer's linked promotion code so the banner CTA has something
    // real to do (apply the code) instead of being a dead button.
    const promoIds = rawOffers.map((o) => o.promotionId).filter((id): id is string => !!id);
    const promos = promoIds.length
      ? await this.prisma.promotion.findMany({
          where: { id: { in: promoIds }, active: true },
          select: { id: true, code: true },
        })
      : [];
    const codeById = new Map(promos.map((p) => [p.id, p.code]));
    // Same public-shape rule as `plans` above: the resolved promoCode is what a client
    // needs; the internal promotionId, the last editor (`updatedBy` is an admin user id)
    // and the row timestamps are not for anonymous callers. Admins read whole rows from
    // `GET /admin/commerce/offers`.
    const offers = rawOffers.map((o) => ({
      id: o.id,
      title: o.title,
      subtitle: o.subtitle,
      body: o.body,
      badge: o.badge,
      ctaLabel: o.ctaLabel,
      region: o.region,
      sortOrder: o.sortOrder,
      active: o.active,
      startsAt: o.startsAt,
      endsAt: o.endsAt,
      promoCode: o.promotionId ? (codeById.get(o.promotionId) ?? null) : null,
    }));

    // currency echoes the region so the client can label prices even before a plan
    // loads (US->USD, CA->CAD, KSA->SAR).
    return { region, currency: REGION_CURRENCY[region], plans, offers };
  }

  async createPlan(dto: CreatePricingPlanDto, adminId: string) {
    const plan = await this.prisma.pricingPlan.create({
      data: {
        tier: dto.tier,
        region: dto.region,
        currency: dto.currency.toUpperCase(),
        unitAmount: dto.unitAmount,
        interval: dto.interval ?? undefined,
        displayName: dto.displayName,
        description: dto.description,
        features: dto.features ?? undefined,
        badge: dto.badge,
        sortOrder: dto.sortOrder ?? 0,
        active: dto.active ?? true,
        updatedBy: adminId,
      },
    });
    return plan;
  }

  async updatePlan(id: string, dto: UpdatePricingPlanDto, adminId: string) {
    const existing = await this.prisma.pricingPlan.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Pricing plan not found.');
    // No provider round-trip: unitAmount here is charged directly at checkout, so
    // an admin price edit takes effect on the very next purchase.
    return this.prisma.pricingPlan.update({
      where: { id },
      data: {
        ...dto,
        currency: dto.currency?.toUpperCase(),
        features: dto.features ?? undefined,
        updatedBy: adminId,
      },
    });
  }

  async deletePlan(id: string) {
    await this.prisma.pricingPlan.delete({ where: { id } });
    return { deleted: true };
  }
}
