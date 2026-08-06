import { BadRequestException } from '@nestjs/common';
import { CatalogSyncService } from './catalog-sync.service';

/**
 * The catalogue mirror is ONE WAY, and these pin the properties that follow from that:
 * every row is offered to the provider (including retired ones, so they are deactivated
 * rather than left sellable), the returned ids are persisted so a re-sync updates
 * instead of duplicating, and one failing row never aborts the rest.
 *
 * Two-way sync is deliberately not built: two systems both accepting price edits need
 * conflict rules that, when they lose a race, charge somebody the wrong amount.
 */
const PLANS = [
  {
    id: 'p1', tier: 'PREMIUM', region: 'US', interval: 'YEAR', currency: 'USD', unitAmount: 19000,
    displayName: 'Premium', description: null, active: true, sortOrder: 2,
    providerProductId: null, providerPriceId: null,
  },
  {
    id: 'p2', tier: 'BASIC', region: 'US', interval: 'ONE_TIME', currency: 'USD', unitAmount: 27900,
    displayName: 'Basic', description: null, active: false, sortOrder: 0,
    providerProductId: 'prod_old', providerPriceId: 'price_old',
  },
];

function make(opts: { sync?: any; configured?: boolean; plans?: any[] } = {}) {
  const updates: any[] = [];
  const prisma: any = {
    pricingPlan: {
      findMany: async () => opts.plans ?? PLANS,
      update: async (args: any) => {
        updates.push(args);
        return args;
      },
    },
  };
  const provider: any = {
    name: 'stripe',
    isConfigured: () => opts.configured ?? true,
    ...(opts.sync === null
      ? {}
      : {
          syncCatalogEntry:
            opts.sync ??
            jest.fn(async (e: any) => ({
              productId: `prod_${e.tier}_${e.region}`,
              priceId: `price_${e.tier}_${e.interval}`,
              priceReplaced: false,
            })),
        }),
  };
  return { svc: new CatalogSyncService(prisma, provider), updates, provider };
}

describe('CatalogSyncService', () => {
  it('mirrors every plan and persists the provider ids back', async () => {
    const { svc, updates } = make();
    const report = await svc.sync();

    expect(report.synced).toBe(2);
    expect(report.failed).toBe(0);
    expect(updates).toHaveLength(2);
    expect(updates[0].data).toEqual({ providerProductId: 'prod_PREMIUM_US', providerPriceId: 'price_PREMIUM_YEAR' });
  });

  it('passes the EXISTING ids so a re-sync updates instead of duplicating', async () => {
    const sync = jest.fn(async () => ({ productId: 'prod_x', priceId: 'price_x', priceReplaced: false }));
    const { svc } = make({ sync });
    await svc.sync();

    const retired = sync.mock.calls.map((c: any[]) => c[0]).find((e: any) => e.tier === 'BASIC');
    expect(retired.existingProductId).toBe('prod_old');
    expect(retired.existingPriceId).toBe('price_old');
  });

  it('mirrors RETIRED plans too, so they are deactivated rather than left sellable', async () => {
    const sync = jest.fn(async () => ({ productId: 'p', priceId: 'x', priceReplaced: false }));
    const { svc } = make({ sync });
    await svc.sync();

    const entries = sync.mock.calls.map((c: any[]) => c[0]);
    expect(entries).toHaveLength(2);
    expect(entries.find((e: any) => e.tier === 'BASIC').active).toBe(false);
  });

  it('sends the LIST price — what a customer pays is computed per checkout', async () => {
    const sync = jest.fn(async () => ({ productId: 'p', priceId: 'x', priceReplaced: false }));
    const { svc } = make({ sync });
    await svc.sync();
    const entries = sync.mock.calls.map((c: any[]) => c[0]);
    expect(entries.find((e: any) => e.tier === 'PREMIUM').unitAmount).toBe(19000);
  });

  it('keeps going when one row fails, and names it in the report', async () => {
    let n = 0;
    const sync = jest.fn(async () => {
      if (n++ === 0) throw new Error('Stripe is unhappy');
      return { productId: 'p', priceId: 'x', priceReplaced: false };
    });
    const { svc, updates } = make({ sync });
    const report = await svc.sync();

    expect(report.failed).toBe(1);
    expect(report.synced).toBe(1);
    expect(report.rows.find((r) => r.error)?.error).toMatch(/unhappy/);
    expect(updates).toHaveLength(1); // only the row that worked was written
  });

  it('counts replaced prices, since a price change means a NEW immutable Price', async () => {
    const { svc } = make({
      sync: jest.fn(async () => ({ productId: 'p', priceId: 'x', priceReplaced: true })),
    });
    const report = await svc.sync();
    expect(report.pricesReplaced).toBe(2);
  });

  it('refuses when the provider has no keys, rather than half-mirroring', async () => {
    const { svc } = make({ configured: false });
    await expect(svc.sync()).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses when the provider cannot mirror a catalogue at all', async () => {
    const { svc } = make({ sync: null });
    await expect(svc.sync()).rejects.toThrow(/cannot mirror/i);
  });

  it('reports status without calling the provider', async () => {
    const { svc, provider } = make();
    const status = await svc.status();
    expect(status).toMatchObject({ totalPlans: 2, activePlans: 1, mirrored: 1, activeUnmirrored: 1 });
    expect(provider.syncCatalogEntry).not.toHaveBeenCalled();
  });
});
