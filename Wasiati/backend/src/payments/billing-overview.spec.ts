import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';

/**
 * The "Manage billing" page (spec §2) must degrade HONESTLY.
 *
 * Everything on it except the card is OURS — we run our own billing cycle, so the
 * plan, the renewal date and the invoices are all in our database. Only the card
 * needs the PSP. So on an environment with no Stripe keys the page still tells the
 * whole truth about the subscription, and simply says card management is
 * unavailable instead of rendering a "Change card" button that can only fail.
 */
describe('billing overview', () => {
  const sub = {
    id: 's1',
    userId: 'u1',
    tier: SubscriptionTier.PREMIUM,
    status: 'ACTIVE',
    interval: 'MONTH',
    currentPeriodEnd: new Date('2026-08-01T00:00:00Z'),
    cancelAtPeriodEnd: false,
    paymentInstrumentId: 'cus_1|pm_1',
    createdAt: new Date(),
  };

  const plan = {
    id: 'p1',
    tier: SubscriptionTier.PREMIUM,
    interval: 'MONTH',
    region: Region.KSA,
    displayName: 'Premium',
    unitAmount: 3900,
    currency: 'SAR',
    active: true,
  };

  const makeService = (opts: {
    configured: boolean;
    subscription?: any;
    card?: any;
    describeThrows?: boolean;
    userRegion?: Region;
  }) => {
    const planQueries: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: opts.userRegion ?? Region.KSA }) },
      subscription: { findFirst: async () => opts.subscription ?? null },
      pricingPlan: {
        findFirst: async ({ where }: any) => {
          planQueries.push(where);
          return where.region === plan.region ? plan : null;
        },
      },
    };
    const invoices: any = { listForUser: async () => [{ id: 'i1', amountMinor: 3900, currency: 'SAR' }] };
    const provider: any = {
      isConfigured: () => opts.configured,
      describeInstrument: async () => {
        if (opts.describeThrows) throw new Error('provider unreachable');
        return opts.card ?? null;
      },
    };
    const svc = new PaymentsService(
      { get: () => undefined } as any,
      prisma,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      invoices,
      provider,
    );
    return { svc, planQueries };
  };

  it('shows plan, renewal, card and invoices when the provider is configured', async () => {
    const { svc } = makeService({
      configured: true,
      subscription: sub,
      card: { brand: 'mada', last4: '4417' },
    });
    const res = await svc.billingOverview('u1');

    expect(res.subscription).toMatchObject({ tier: 'PREMIUM', currentPeriodEnd: sub.currentPeriodEnd });
    expect(res.plan).toMatchObject({ displayName: 'Premium', unitAmount: 3900, currency: 'SAR' });
    expect(res.card).toEqual({ brand: 'mada', last4: '4417' });
    expect(res.canChangeCard).toBe(true);
    expect(res.invoices).toHaveLength(1);
  });

  it('WITHOUT provider keys: everything of ours still shows; the card silently does not', async () => {
    const { svc } = makeService({ configured: false, subscription: sub });
    const res = await svc.billingOverview('u1');

    // The honest part: we still know all of this without a PSP.
    expect(res.subscription).toMatchObject({ tier: 'PREMIUM' });
    expect(res.plan).toMatchObject({ unitAmount: 3900, currency: 'SAR' });
    expect(res.invoices).toHaveLength(1);
    // A card IS stored — we just cannot describe it, and we do not pretend to.
    expect(res.hasPaymentMethod).toBe(true);
    expect(res.card).toBeNull();
    // …so the app must not offer an action that cannot work.
    expect(res.canChangeCard).toBe(false);
  });

  it('prices the renewal line from the ACCOUNT region — same rule as everywhere else', async () => {
    const { svc, planQueries } = makeService({ configured: true, subscription: sub, userRegion: Region.KSA });
    await svc.billingOverview('u1');
    expect(planQueries[0]).toMatchObject({ region: Region.KSA, tier: 'PREMIUM', interval: 'MONTH' });
  });

  it('a user with no subscription gets a truthful empty page, not an error', async () => {
    const { svc } = makeService({ configured: true, subscription: null });
    const res = await svc.billingOverview('u1');

    expect(res.subscription).toBeNull();
    expect(res.plan).toBeNull();
    expect(res.hasPaymentMethod).toBe(false);
    // Nothing to change the card ON.
    expect(res.canChangeCard).toBe(false);
  });

  it('refuses to start a change-card flow when there is no subscription', async () => {
    const { svc } = makeService({ configured: true, subscription: null });
    await expect(svc.changePaymentMethod('u1', 'https://app.wasiati.com/s', 'https://app.wasiati.com/c')).rejects.toThrow(
      /no active subscription/i,
    );
  });
});
