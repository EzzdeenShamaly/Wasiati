import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';
import { SubscriptionsService } from './subscriptions.service';

/**
 * A one-time purchase is "yours for life" — a paid-in-full entitlement, not a
 * billing cycle. The trap: the recurring fulfil path used to match subscriptions
 * by (userId, tier) alone, so a later recurring event for the SAME tier matched
 * the ONE_TIME row and stamped an interval + currentPeriodEnd onto it — silently
 * converting a lifetime entitlement the customer paid for into a renewing,
 * dunnable, cancellable subscription. These pin that a lifetime row survives
 * every later recurring event, the renewal cron, and unrelated refunds.
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

/** The lifetime purchase every test starts from. */
const lifetimeRow = () => ({
  id: 's_lifetime',
  userId: 'u1',
  tier: SubscriptionTier.BASIC,
  interval: 'ONE_TIME',
  status: 'ACTIVE',
  currentPeriodEnd: null,
  createdAt: new Date('2026-01-01T00:00:00Z'),
});

function makePayments(store: ReturnType<typeof subscriptionStore>) {
  const prisma: any = { subscription: store };
  return new PaymentsService(
    { get: () => undefined } as any,
    prisma,
    {} as any, // notifications
    {} as any, // credits
    { handleQualifyingPurchase: async () => undefined, rejectForRefund: async () => undefined } as any,
    {} as any, // promotions
    { record: async () => undefined, markRefunded: async () => undefined } as any,
    {} as any, // provider
  );
}

/** What Stripe sends after a successful RECURRING purchase of `tier`. */
const recurringApproval = (tier: SubscriptionTier, interval: 'MONTH' | 'YEAR') => ({
  id: `evt_${tier}_${interval}`,
  type: 'payment_approved',
  providerPaymentId: `pi_${tier}`,
  amountMinor: 1900,
  currency: 'USD',
  paymentInstrumentId: 'cus_1|pm_1',
  metadata: { userId: 'u1', tier, interval, planId: 'plan_x', basisMinor: '1900', basisCurrency: 'USD' },
});

describe('a lifetime (ONE_TIME) purchase survives later recurring events', () => {
  it('a recurring fulfil of the SAME tier creates its own row and leaves the lifetime row untouched', async () => {
    const store = subscriptionStore([lifetimeRow()]);
    const svc = makePayments(store);

    await (svc as any).onPaymentApproved(recurringApproval(SubscriptionTier.BASIC, 'MONTH'));

    // The lifetime entitlement is EXACTLY as paid for: one-time, no renewal date.
    const lifetime = store.rows.find((r) => r.id === 's_lifetime')!;
    expect(lifetime.interval).toBe('ONE_TIME');
    expect(lifetime.currentPeriodEnd).toBeNull();
    expect(lifetime.status).toBe('ACTIVE');

    // The recurring purchase got its OWN subscription row.
    const recurring = store.rows.filter((r) => r.id !== 's_lifetime');
    expect(recurring).toHaveLength(1);
    expect(recurring[0]).toMatchObject({ interval: 'MONTH', status: 'ACTIVE' });
    expect(recurring[0].currentPeriodEnd).toBeInstanceOf(Date);
  });

  it('the renewal cron never charges the lifetime row, even after a same-tier recurring event', async () => {
    const store = subscriptionStore([lifetimeRow()]);
    await (makePayments(store) as any).onPaymentApproved(recurringApproval(SubscriptionTier.BASIC, 'MONTH'));

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
            displayName: 'Basic',
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

    // Far in the future: everything with a period end is overdue.
    await subs.runBillingCycle(new Date('2027-06-01T04:00:00Z'));

    // Only the recurring row renews; the lifetime row was never touched. If the
    // recurring fulfil had clobbered it, s_lifetime would carry a period end and
    // be charged here — a lifetime customer billed monthly.
    expect(charged).not.toContain('s_lifetime');
    const lifetime = store.rows.find((r) => r.id === 's_lifetime')!;
    expect(lifetime).toMatchObject({ interval: 'ONE_TIME', status: 'ACTIVE', currentPeriodEnd: null });
  });

  it('refunding a RECURRING payment cancels the recurring row, never the lifetime row', async () => {
    const store = subscriptionStore([
      lifetimeRow(),
      {
        id: 's_recur',
        userId: 'u1',
        tier: SubscriptionTier.STANDARD,
        interval: 'YEAR',
        status: 'ACTIVE',
        currentPeriodEnd: new Date('2026-12-01T00:00:00Z'),
        createdAt: new Date('2026-02-01T00:00:00Z'),
      },
    ]);
    const svc = makePayments(store);

    await (svc as any).onPaymentRefunded(
      { userId: 'u1', tier: 'STANDARD', interval: 'YEAR' },
      'pi_refunded',
    );

    expect(store.rows.find((r) => r.id === 's_recur')!.status).toBe('CANCELED');
    // The lifetime purchase was not the thing refunded — it stays paid for.
    expect(store.rows.find((r) => r.id === 's_lifetime')!.status).toBe('ACTIVE');
  });
});
