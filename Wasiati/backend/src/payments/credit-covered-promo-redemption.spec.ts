import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';

/**
 * A promo redeemed on the credit-covered path must COUNT.
 *
 * When amountDue reaches 0 — the discount plus account credit settled the whole price —
 * checkout fulfils immediately: the provider never sees the purchase, so there is no
 * webhook, and onPaymentApproved (where recordRedemption lived) never runs. The zero-due
 * branch recorded the invoice and qualified the referral, and never touched the promo
 * counter.
 *
 * That is not an edge case, it is a whole class of promo: a 100%-off code ALWAYS lands
 * here, because the discount itself is what makes amountDue 0. So a "first 100 customers
 * free" code with maxRedemptions: 100 was redeemable forever — validate() enforces the cap
 * by reading timesRedeemed (promotions.service.ts:254), and this path never moved it.
 */
describe('checkout: a credit-covered purchase still redeems its promo', () => {
  const PLAN = {
    id: 'premium-US',
    tier: SubscriptionTier.PREMIUM,
    interval: 'YEAR',
    region: Region.US,
    displayName: 'Premium',
    active: true,
    currency: 'USD',
    unitAmount: 20000,
  };

  function makeService(promo: { amountMinor: number; promotionId: string | null }, creditMinor: number) {
    const redemptions: any[] = [];
    const sessions: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findMany: async () => [PLAN] },
      // fulfil() activates the subscription on this path (no webhook will).
      subscription: {
        findFirst: async () => null,
        create: async ({ data }: any) => ({ id: 'sub1', ...data }),
        update: async ({ data }: any) => ({ id: 'sub1', ...data }),
        updateMany: async () => ({ count: 0 }), // the supersede-other-tiers sweep
      },
    };
    const credits: any = {
      consume: async (p: any) => Math.min(creditMinor, p.requestedMinor),
      grant: async () => ({ granted: true }),
    };
    const promotions: any = {
      applyToAmount: async () => promo,
      recordRedemption: async (promotionId: string, providerPaymentId?: string) => {
        redemptions.push({ promotionId, providerPaymentId });
      },
    };
    const provider: any = {
      createHostedPayment: async (req: any) => {
        sessions.push(req);
        return { redirectUrl: 'https://pay.example/x', sessionId: 'cs_1' };
      },
    };
    const svc = new PaymentsService(
      { get: () => undefined } as any,
      prisma,
      {} as any,
      credits,
      { pendingDiscountPercent: async () => 0, handleQualifyingPurchase: async () => undefined } as any,
      promotions,
      { record: async () => undefined } as any,
      provider,
    );
    return { svc, redemptions, sessions };
  }

  const checkout = (svc: PaymentsService) =>
    svc.createCheckoutSession({
      userId: 'u1',
      tier: SubscriptionTier.PREMIUM,
      interval: 'YEAR',
      promoCode: 'FOUNDERS100',
      successUrl: 'https://app.wasiati.com/s',
      cancelUrl: 'https://app.wasiati.com/c',
    });

  // THE class of promo that can never reach a webhook: 100% off.
  it('a 100%-off code is recorded as redeemed — its cap is real', async () => {
    const { svc, redemptions, sessions } = makeService({ amountMinor: 0, promotionId: 'promo_free' }, 0);
    await expect(checkout(svc)).resolves.toMatchObject({ fullyCoveredByCredit: true });

    expect(sessions).toHaveLength(0); // the provider never saw it — no webhook can come
    expect(redemptions).toEqual([
      { promotionId: 'promo_free', providerPaymentId: expect.stringMatching(/^credit:/) },
    ]);
  });

  it('a partial promo whose remainder account credit covers is redeemed too', async () => {
    // $200 -> $160 by promo; $160 of credit settles it. Same absent webhook.
    const { svc, redemptions } = makeService({ amountMinor: 16000, promotionId: 'promo_20' }, 16000);
    await expect(checkout(svc)).resolves.toMatchObject({ fullyCoveredByCredit: true });
    expect(redemptions.map((r) => r.promotionId)).toEqual(['promo_20']);
  });

  // The synthetic key claims the same per-payment idempotency marker the webhook pair
  // uses (`redeem:<promo>:<id>`); a `credit:` prefix cannot collide with a provider id.
  it('keys the redemption to THIS attempt, not to nothing', async () => {
    const { svc, redemptions } = makeService({ amountMinor: 0, promotionId: 'promo_free' }, 0);
    await checkout(svc);
    expect(redemptions[0].providerPaymentId).toContain(PLAN.id); // attemptId = planId:timestamp
  });

  it('no promo, no redemption — credit-covered checkouts without a code stay silent', async () => {
    const { svc, redemptions } = makeService({ amountMinor: PLAN.unitAmount, promotionId: null }, 20000);
    await expect(
      svc.createCheckoutSession({
        userId: 'u1',
        tier: SubscriptionTier.PREMIUM,
        interval: 'YEAR',
        successUrl: 'https://app.wasiati.com/s',
        cancelUrl: 'https://app.wasiati.com/c',
      }),
    ).resolves.toMatchObject({ fullyCoveredByCredit: true });
    expect(redemptions).toEqual([]);
  });

  it('a promo on a CARD checkout is not redeemed here — that is the webhook’s job', async () => {
    // $160 due, no credit: the buyer goes to the hosted page. Counting at session
    // creation would redeem codes for checkouts that are then abandoned.
    const { svc, redemptions, sessions } = makeService({ amountMinor: 16000, promotionId: 'promo_20' }, 0);
    await expect(checkout(svc)).resolves.toMatchObject({ checkoutUrl: 'https://pay.example/x' });
    expect(sessions).toHaveLength(1);
    expect(redemptions).toEqual([]);
  });
});
