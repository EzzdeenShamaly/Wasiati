import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';
import { SubscriptionsService } from './subscriptions.service';

/**
 * Switching tiers must SUPERSEDE, never STACK.
 *
 * The trap: fulfil matched subscriptions by (userId, tier), so paying for a
 * second tier while a recurring plan was live created a SECOND active row. The
 * renewal cron charges every live row — the customer was double-billed forever —
 * and every self-serve query is newest-first, so the older plan vanished from
 * billingOverview and could not even be cancelled. These pin the invariant that
 * at most ONE live recurring subscription exists per user, and that the billing
 * page / cancel always target the row that is actually taking money.
 */

type Row = Record<string, any>;

/** In-memory stand-in for prisma.subscription, faithful to the operators the services use. */
function subscriptionStore(seed: Row[]) {
  const rows: Row[] = seed.map((r) => ({
    cancelAtPeriodEnd: false,
    failedPaymentCount: 0,
    canceledAt: null,
    currentPeriodEnd: null,
    createdAt: new Date(0),
    ...r,
  }));
  let nextId = 1000;
  const matches = (row: Row, where: Row = {}) =>
    Object.entries(where).every(([k, cond]) => {
      if (cond !== null && typeof cond === 'object' && !(cond instanceof Date)) {
        if ('in' in cond) return (cond.in as any[]).includes(row[k]);
        if ('not' in cond) return row[k] !== cond.not;
        if ('lte' in cond) return row[k] !== null && row[k] <= cond.lte;
      }
      if (row[k] instanceof Date && cond instanceof Date) return +row[k] === +cond;
      return row[k] === cond;
    });
  const sorted = (orderBy?: Row) => {
    const rs = [...rows];
    if (orderBy?.createdAt === 'desc') rs.sort((a, b) => +b.createdAt - +a.createdAt);
    return rs;
  };
  return {
    rows,
    findFirst: async ({ where, orderBy }: Row = {}) => sorted(orderBy).find((r) => matches(r, where)) ?? null,
    findMany: async ({ where }: Row = {}) => rows.filter((r) => matches(r, where)),
    create: async ({ data }: Row) => {
      const row = { id: `sub_${nextId++}`, cancelAtPeriodEnd: false, failedPaymentCount: 0, canceledAt: null, currentPeriodEnd: null, createdAt: new Date(), ...data };
      rows.push(row);
      return row;
    },
    update: async ({ where, data }: Row) => {
      const row = rows.find((r) => r.id === where.id);
      if (!row) throw new Error(`no subscription ${where.id}`);
      Object.assign(row, data);
      return row;
    },
    updateMany: async ({ where, data }: Row) => {
      const hit = rows.filter((r) => matches(r, where));
      hit.forEach((r) => Object.assign(r, data));
      return { count: hit.length };
    },
  };
}

const live = (rows: Row[]) =>
  rows.filter((r) => ['ACTIVE', 'PAST_DUE'].includes(r.status) && ['MONTH', 'YEAR'].includes(r.interval));

function makePayments(store: ReturnType<typeof subscriptionStore>) {
  const prisma: any = {
    subscription: store,
    user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
    pricingPlan: {
      findFirst: async ({ where }: any) => ({
        id: 'plan_x',
        tier: where.tier,
        interval: where.interval,
        region: Region.US,
        displayName: String(where.tier),
        unitAmount: 1900,
        currency: 'USD',
        active: true,
      }),
    },
    burialPrepaymentPlan: { findFirst: async () => null },
  };
  return new PaymentsService(
    { get: () => undefined } as any,
    prisma,
    {} as any, // notifications
    {} as any, // credits
    { handleQualifyingPurchase: async () => undefined } as any,
    {} as any, // promotions
    { record: async () => undefined, listForUser: async () => [] } as any,
    { isConfigured: () => false, describeInstrument: async () => null } as any,
  );
}

/** What Stripe sends after the customer paid for a recurring plan. */
const approval = (tier: SubscriptionTier, interval: 'MONTH' | 'YEAR') => ({
  id: `evt_${tier}_${interval}`,
  type: 'payment_approved',
  providerPaymentId: `pi_${tier}`,
  amountMinor: 1900,
  currency: 'USD',
  paymentInstrumentId: 'cus_1|pm_new',
  metadata: { userId: 'u1', tier, interval, planId: 'plan_x', basisMinor: '1900', basisCurrency: 'USD' },
});

const standardSub = () => ({
  id: 's_std',
  userId: 'u1',
  tier: SubscriptionTier.STANDARD,
  interval: 'YEAR',
  status: 'ACTIVE',
  currentPeriodEnd: new Date('2026-12-01T00:00:00Z'),
  paymentInstrumentId: 'cus_1|pm_old',
  createdAt: new Date('2026-01-01T00:00:00Z'),
});

describe('buying a second tier supersedes the first', () => {
  it('leaves exactly ONE live recurring subscription — the new one', async () => {
    const store = subscriptionStore([standardSub()]);
    await (makePayments(store) as any).onPaymentApproved(approval(SubscriptionTier.PREMIUM, 'YEAR'));

    const stillLive = live(store.rows);
    expect(stillLive).toHaveLength(1);
    expect(stillLive[0].tier).toBe(SubscriptionTier.PREMIUM);

    const old = store.rows.find((r) => r.id === 's_std')!;
    expect(old.status).toBe('CANCELED');
    expect(old.canceledAt).toBeInstanceOf(Date);
  });

  it('the renewal cron therefore charges exactly ONE subscription — no double-billing', async () => {
    const store = subscriptionStore([standardSub()]);
    await (makePayments(store) as any).onPaymentApproved(approval(SubscriptionTier.PREMIUM, 'YEAR'));

    const charged: string[] = [];
    const subs = new SubscriptionsService(
      {
        subscription: store,
        user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
        pricingPlan: {
          findFirst: async ({ where }: any) => ({
            id: 'plan_x',
            tier: where.tier,
            interval: where.interval,
            region: Region.US,
            displayName: String(where.tier),
            unitAmount: 1900,
            currency: 'USD',
            active: true,
          }),
        },
      } as any,
      { sendEmail: async () => undefined } as any,
      { consume: async () => 0, grant: async () => undefined } as any,
      { record: async () => undefined } as any,
      {
        chargeStoredInstrument: async (req: any) => {
          charged.push(req.metadata.subscriptionId);
          return { approved: true, providerPaymentId: `pi_renew_${charged.length}` };
        },
      } as any,
    );

    // Far enough out that BOTH period ends have passed — if the old plan were
    // still live, this run would charge the customer twice.
    await subs.runBillingCycle(new Date('2028-01-01T04:00:00Z'));

    expect(charged).toHaveLength(1);
    expect(charged).not.toContain('s_std');
  });

  it('a replayed fulfilment (approved + captured pair) changes nothing further', async () => {
    const store = subscriptionStore([standardSub()]);
    const svc = makePayments(store);
    await (svc as any).onPaymentApproved(approval(SubscriptionTier.PREMIUM, 'YEAR'));
    await (svc as any).onPaymentApproved({ ...approval(SubscriptionTier.PREMIUM, 'YEAR'), id: 'evt_captured' });

    expect(live(store.rows)).toHaveLength(1);
    expect(store.rows).toHaveLength(2); // no third row appeared
  });
});

describe('the billing page and cancel always find the plan that is billing', () => {
  it('billingOverview shows the LIVE plan even when a canceled row is newer', async () => {
    const store = subscriptionStore([
      standardSub(), // ACTIVE, created January
      {
        id: 's_dead',
        userId: 'u1',
        tier: SubscriptionTier.PREMIUM,
        interval: 'YEAR',
        status: 'CANCELED',
        canceledAt: new Date('2026-06-01T00:00:00Z'),
        createdAt: new Date('2026-03-01T00:00:00Z'), // newer than the live one
      },
    ]);
    const svc = makePayments(store);

    const overview = await svc.billingOverview('u1');
    // Newest-first would show the dead PREMIUM row and hide the plan still
    // charging the customer — the exact "invisible, uncancellable" failure.
    expect(overview.subscription?.tier).toBe(SubscriptionTier.STANDARD);
    expect(overview.subscription?.status).toBe('ACTIVE');

    const res = await svc.cancelSubscription('u1');
    expect(res.scheduledCancellation).toBe(true);
    expect(store.rows.find((r) => r.id === 's_std')!.cancelAtPeriodEnd).toBe(true);
  });

  it('cancel targets the billing plan, never a newer lifetime ONE_TIME row', async () => {
    const store = subscriptionStore([
      { ...standardSub(), interval: 'MONTH' },
      {
        id: 's_life',
        userId: 'u1',
        tier: SubscriptionTier.BASIC,
        interval: 'ONE_TIME',
        status: 'ACTIVE',
        currentPeriodEnd: null,
        createdAt: new Date('2026-06-01T00:00:00Z'), // newer than the recurring one
      },
    ]);
    const svc = makePayments(store);

    await svc.cancelSubscription('u1');

    // The recurring plan stops; the lifetime purchase is not what cancel means.
    expect(store.rows.find((r) => r.id === 's_std')!.cancelAtPeriodEnd).toBe(true);
    expect(store.rows.find((r) => r.id === 's_life')!).toMatchObject({
      status: 'ACTIVE',
      cancelAtPeriodEnd: false,
    });
  });

  it('superseding never touches a lifetime ONE_TIME row', async () => {
    const store = subscriptionStore([
      {
        id: 's_life',
        userId: 'u1',
        tier: SubscriptionTier.BASIC,
        interval: 'ONE_TIME',
        status: 'ACTIVE',
        currentPeriodEnd: null,
        createdAt: new Date('2026-01-01T00:00:00Z'),
      },
    ]);
    await (makePayments(store) as any).onPaymentApproved(approval(SubscriptionTier.STANDARD, 'YEAR'));

    // The new recurring plan exists AND the lifetime entitlement still stands.
    expect(live(store.rows)).toHaveLength(1);
    expect(store.rows.find((r) => r.id === 's_life')!).toMatchObject({
      status: 'ACTIVE',
      interval: 'ONE_TIME',
    });
  });
});
