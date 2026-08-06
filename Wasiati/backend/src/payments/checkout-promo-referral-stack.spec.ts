import { BadRequestException } from '@nestjs/common';
import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';

/**
 * A promo code and a referred friend's discount STACK, and they compound.
 *
 * Both reductions land on the same checkout — neither suppresses the other — and the
 * referral percentage is taken off the figure the promo already reduced
 * (payments.service.ts, step 2). That ordering is worth pinning: "20% + 10%" reads like
 * 30% off, but compounding makes it 28%, and the difference is real money on every
 * referred purchase. Nothing tested this before; the other checkout specs stub
 * `pendingDiscountPercent` to 0, so the stack was entirely undefended.
 *
 * Also pinned here: a code the buyer typed that we cannot honour must FAIL LOUDLY.
 * It used to return full price silently, which is how a tier-restricted code (valid in
 * the tier-less preview, invalid at checkout) turned into "the promo didn't work".
 */
describe('checkout: promo + referral discounts stack', () => {
  const PLAN = {
    id: 'premium-US',
    tier: SubscriptionTier.PREMIUM,
    interval: 'YEAR',
    region: Region.US,
    displayName: 'Premium',
    active: true,
    currency: 'USD',
    unitAmount: 20000, // $200.00 in minor units
  };

  /**
   * @param promo       what PromotionsService.applyToAmount should return
   * @param referralPct the friend's discount percentage
   */
  const makeService = (
    promo: { amountMinor: number; promotionId: string | null; rejectedReason?: string },
    referralPct: number,
  ) => {
    const charged: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findMany: async () => [PLAN] },
    };
    const credits: any = { consume: async () => 0 };
    const referrals: any = { pendingDiscountPercent: async () => referralPct };
    const promotions: any = { applyToAmount: async () => promo };
    const provider: any = {
      createHostedPayment: async (req: any) => {
        charged.push(req);
        return { redirectUrl: 'https://pay.example/x', sessionId: 'cs_1' };
      },
    };
    const svc = new PaymentsService(
      { get: () => undefined } as any,
      prisma,
      {} as any,
      credits,
      referrals,
      promotions,
      { record: async () => undefined } as any,
      provider,
    );
    return { svc, charged };
  };

  const urls = { successUrl: 'https://app.wasiati.com/s', cancelUrl: 'https://app.wasiati.com/c' };
  const checkout = (svc: PaymentsService, promoCode?: string) =>
    svc.createCheckoutSession({
      userId: 'u1',
      tier: SubscriptionTier.PREMIUM,
      interval: 'YEAR',
      promoCode,
      ...urls,
    });

  it('applies BOTH: a 20% promo and a referred friend’s 10% compound to 28% off', async () => {
    // promo took $200 -> $160; the referral 10% then comes off THAT, not off $200.
    const { svc, charged } = makeService({ amountMinor: 16000, promotionId: 'promo_1' }, 10);
    await checkout(svc, 'SAVE20');

    expect(charged[0].amountMinor).toBe(14400); // $144.00 — not $140 (additive), not $160/$180
  });

  it('applies the promo alone when the buyer has no referral', async () => {
    const { svc, charged } = makeService({ amountMinor: 16000, promotionId: 'promo_1' }, 0);
    await checkout(svc, 'SAVE20');
    expect(charged[0].amountMinor).toBe(16000);
  });

  it('applies the referral alone when no promo code is given', async () => {
    const { svc, charged } = makeService({ amountMinor: PLAN.unitAmount, promotionId: null }, 10);
    await checkout(svc);
    expect(charged[0].amountMinor).toBe(18000);
  });

  it('keeps both discounts recorded in metadata — neither is dropped', async () => {
    const { svc, charged } = makeService({ amountMinor: 16000, promotionId: 'promo_1' }, 10);
    await checkout(svc, 'SAVE20');

    expect(charged[0].metadata).toMatchObject({
      promotionId: 'promo_1',
      referralDiscountPercent: '10',
    });
  });

  it('rejects a code it cannot honour instead of silently charging full price', async () => {
    const { svc, charged } = makeService(
      {
        amountMinor: PLAN.unitAmount,
        promotionId: null,
        rejectedReason: 'This code does not apply to the selected plan.',
      },
      10,
    );

    await expect(checkout(svc, 'LAUNCH25')).rejects.toBeInstanceOf(BadRequestException);
    // The buyer is NOT sent to a payment page at the undiscounted price.
    expect(charged).toHaveLength(0);
  });

  it('does not consult the promo engine at all for an empty code string', async () => {
    let called = false;
    const { svc, charged } = makeService({ amountMinor: PLAN.unitAmount, promotionId: null }, 0);
    (svc as any).promotions.applyToAmount = async () => {
      called = true;
      return { amountMinor: PLAN.unitAmount, promotionId: null };
    };

    await checkout(svc, '   ');
    expect(called).toBe(false);
    expect(charged[0].amountMinor).toBe(PLAN.unitAmount);
  });
});
