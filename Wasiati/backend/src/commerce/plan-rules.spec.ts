import { BadRequestException } from '@nestjs/common';
import { PriceInterval, Region, SubscriptionTier } from '@prisma/client';
import { assertPurchasable, isPurchasable } from './plan-rules';
import { PricingService } from './pricing.service';
import { PaymentsService } from './../payments/payments.service';

/**
 * Ultimate is a SUBSCRIPTION tier. Its reason to exist is burial pre-planning paid
 * by contributions over 3/5/10 years (spec §2) — inherently recurring — so it
 * cannot be sold one-time. Standard and Premium are software entitlements, so
 * "pay once, keep it for life" is coherent there and must keep working.
 */
describe('plan rules — Ultimate cannot be bought one-time', () => {
  it('refuses ULTIMATE on the one-time cycle', () => {
    expect(isPurchasable(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME)).toBe(false);
    expect(() => assertPurchasable(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME)).toThrow(BadRequestException);
    expect(() => assertPurchasable(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME)).toThrow(/subscription/i);
  });

  it('allows ULTIMATE on every RECURRING cycle', () => {
    expect(isPurchasable(SubscriptionTier.ULTIMATE, PriceInterval.MONTH)).toBe(true);
    expect(isPurchasable(SubscriptionTier.ULTIMATE, PriceInterval.YEAR)).toBe(true);
  });

  it('leaves the software tiers sellable on every cycle, one-time included', () => {
    for (const tier of [SubscriptionTier.STANDARD, SubscriptionTier.PREMIUM]) {
      for (const interval of [PriceInterval.ONE_TIME, PriceInterval.MONTH, PriceInterval.YEAR]) {
        expect(isPurchasable(tier, interval)).toBe(true);
      }
    }
  });
});

describe('catalog marks what cannot be sold', () => {
  const plan = (tier: SubscriptionTier, interval: PriceInterval) => ({
    id: `${tier}-${interval}`,
    tier,
    interval,
    region: Region.US,
    badge: null,
    sortOrder: 1,
  });

  const service = (plans: any[]) => {
    const prisma: any = {
      pricingPlan: { findMany: async () => plans },
      offer: { findMany: async () => [] },
      promotion: { findMany: async () => [] },
      // No subscriptions yet → the seeded badge is kept (popularTier === null).
      subscription: { groupBy: async () => [] },
    };
    return new PricingService(prisma);
  };

  it('flags an Ultimate one-time row unpurchasable, even if an admin created one', async () => {
    // The seed no longer writes this row — but an admin can, via the console, and
    // the catalog must not present it as buyable.
    const catalog = await service([
      plan(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME),
      plan(SubscriptionTier.ULTIMATE, PriceInterval.MONTH),
      plan(SubscriptionTier.STANDARD, PriceInterval.ONE_TIME),
    ]).getCatalog(Region.US);

    const by = (id: string) => catalog.plans.find((p: any) => p.id === id) as any;
    expect(by('ULTIMATE-ONE_TIME').purchasable).toBe(false);
    expect(by('ULTIMATE-MONTH').purchasable).toBe(true);
    expect(by('STANDARD-ONE_TIME').purchasable).toBe(true);
  });

  it('still returns the row rather than dropping it, so the app can explain the absence', async () => {
    const catalog = await service([plan(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME)]).getCatalog(Region.US);
    expect(catalog.plans).toHaveLength(1);
  });
});

describe('checkout enforces it server-side', () => {
  /** A user + catalog where the requested plan exists and is otherwise buyable. */
  const service = (tier: SubscriptionTier, interval: PriceInterval, region = Region.US) => {
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region }) },
      pricingPlan: {
        findMany: async () => [
          {
            id: 'p1',
            tier,
            interval,
            region,
            currency: 'USD',
            unitAmount: 39900,
            displayName: 'Ultimate',
            active: true,
          },
        ],
      },
    };
    return new PaymentsService(
      { get: () => undefined } as any, // config: no PAYMENT_RETURN_HOSTS → URL guard is a no-op
      prisma,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
    );
  };

  const urls = { successUrl: 'https://app.wasiati.com/s', cancelUrl: 'https://app.wasiati.com/c' };

  it('REJECTS a one-time checkout for ULTIMATE — the hidden card is not the enforcement', async () => {
    const svc = service(SubscriptionTier.ULTIMATE, PriceInterval.ONE_TIME);
    await expect(
      svc.createCheckoutSession({ userId: 'u1', tier: SubscriptionTier.ULTIMATE, interval: PriceInterval.ONE_TIME, ...urls }),
    ).rejects.toThrow(/one-time purchase/i);
  });

  it('does not block a one-time checkout for a software tier', async () => {
    const svc = service(SubscriptionTier.STANDARD, PriceInterval.ONE_TIME);
    // Proceeds past the rule and fails later on the un-stubbed promo/credit path —
    // the point is that it is NOT rejected for being one-time.
    await expect(
      svc.createCheckoutSession({ userId: 'u1', tier: SubscriptionTier.STANDARD, interval: PriceInterval.ONE_TIME, ...urls }),
    ).rejects.not.toThrow(/one-time purchase/i);
  });
});
