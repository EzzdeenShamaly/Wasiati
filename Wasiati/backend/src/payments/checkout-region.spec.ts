import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';

/**
 * Checkout is ALWAYS authenticated, so the price a member pays — and the currency
 * it is denominated in — must come from their account. A client-supplied region
 * here would be worse than the catalog regression it mirrors: not just a wrong
 * label, but paying the cheapest market's price by editing one field.
 *
 * `CreateCheckoutDto` has no `region`, so this is enforced by construction; these
 * pin the behaviour so it cannot be reintroduced.
 */
describe('checkout prices from the ACCOUNT region', () => {
  const planFor = (region: Region) => {
    const prices: Record<Region, { currency: string; unitAmount: number }> = {
      KSA: { currency: 'SAR', unitAmount: 3900 },
      US: { currency: 'USD', unitAmount: 1900 },
      CA: { currency: 'CAD', unitAmount: 2600 },
    };
    return {
      id: `premium-${region}`,
      tier: SubscriptionTier.PREMIUM,
      interval: 'MONTH',
      region,
      displayName: 'Premium',
      active: true,
      ...prices[region],
    };
  };

  /** Captures what the provider was ultimately asked to charge. */
  const makeService = (accountRegion: Region) => {
    const queried: any[] = [];
    const charged: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: accountRegion }) },
      pricingPlan: {
        findMany: async ({ where }: any) => {
          queried.push(where);
          return [planFor(where.region as Region)];
        },
      },
    };
    const credits: any = { consume: async () => 0 };
    const referrals: any = { pendingDiscountPercent: async () => 0 };
    const promotions: any = {};
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
    return { svc, queried, charged };
  };

  const urls = { successUrl: 'https://app.wasiati.com/s', cancelUrl: 'https://app.wasiati.com/c' };

  it('bills a KSA member in SAR at the KSA price', async () => {
    const { svc, queried, charged } = makeService(Region.KSA);
    await svc.createCheckoutSession({ userId: 'u1', tier: SubscriptionTier.PREMIUM, interval: 'MONTH', ...urls });

    expect(queried[0].region).toBe(Region.KSA);
    expect(charged[0]).toMatchObject({ currency: 'SAR', amountMinor: 3900 });
  });

  it('IGNORES a region smuggled into the call — the account decides', async () => {
    const { svc, queried, charged } = makeService(Region.KSA);
    // What a tampered client would send. The DTO drops it; the service has no
    // parameter for it to land in.
    await svc.createCheckoutSession({
      userId: 'u1',
      tier: SubscriptionTier.PREMIUM,
      interval: 'MONTH',
      region: Region.US,
      ...urls,
    } as any);

    expect(queried[0].region).toBe(Region.KSA);
    expect(charged[0].currency).toBe('SAR');
  });

  it('bills a US member in USD at the US price', async () => {
    const { svc, charged } = makeService(Region.US);
    await svc.createCheckoutSession({ userId: 'u1', tier: SubscriptionTier.PREMIUM, interval: 'MONTH', ...urls });
    expect(charged[0]).toMatchObject({ currency: 'USD', amountMinor: 1900 });
  });
});
