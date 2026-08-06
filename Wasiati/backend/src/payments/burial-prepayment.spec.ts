import { BadRequestException } from '@nestjs/common';
import { PaymentsService } from './payments.service';

/**
 * Burial is PREPAID ESCROW, not installments (docs/DECISIONS.md §6). These tests pin
 * the two properties that keep it out of consumer-credit and preneed-insurance law:
 *
 *   1. a part-funded plan NEVER blocks cancelling the subscription, and cancelling
 *      returns every riyal contributed — it is the customer's money, held in trust;
 *   2. the plan never self-completes — being fully funded is reached only by
 *      contributing the full price.
 *
 * The service previously did the opposite: `assertCancellable()` threw while a plan
 * was unmatured, which is exactly the walk-away-impossible obligation that makes a
 * payment plan into credit.
 */
type Plan = {
  id: string;
  userId: string;
  currency: string;
  totalAmount: number;
  amountPaid: number;
  status: string;
  maturesAt: Date | null;
  refundDueMinor?: number | null;
  cancelledAt?: Date | null;
};

function makeDb(plans: Plan[], subs: any[] = []) {
  const planApi = {
    findFirst: async ({ where }: any) =>
      plans.find((p) => p.userId === where.userId && (!where.status || p.status === where.status)) ?? null,
    findMany: async ({ where }: any) => {
      // The refund queue filters on status + refundDueMinor rather than userId.
      if (where?.status === 'CANCELLED' && where?.refundDueMinor?.gt !== undefined) {
        return plans
          .filter((p) => p.status === 'CANCELLED' && (p.refundDueMinor ?? 0) > where.refundDueMinor.gt)
          .map((p) => ({ ...p, user: { id: p.userId, email: `${p.userId}@x.com`, region: 'KSA' } }));
      }
      return plans.filter((p) => p.userId === where.userId);
    },
    // Prisma returns a DETACHED object. Handing back the live reference would let a
    // later update() mutate the caller's copy, hiding read-then-write bugs.
    findUnique: async ({ where }: any) => {
      const p = plans.find((x) => x.id === where.id);
      return p ? { ...p } : null;
    },
    update: async ({ where, data }: any) => {
      const p = plans.find((x) => x.id === where.id)!;
      Object.assign(p, data);
      return p;
    },
    create: async ({ data }: any) => {
      const p = { id: `p${plans.length + 1}`, ...data };
      plans.push(p);
      return p;
    },
  };
  const prisma: any = {
    burialPrepaymentPlan: planApi,
    subscription: {
      findFirst: async () => subs[0] ?? null,
      update: async ({ data }: any) => Object.assign(subs[0], data),
    },
  };
  return prisma;
}

// (config, prisma, notifications, credits, referrals, promotions, invoices, provider)
const svc = (prisma: any) =>
  new PaymentsService({} as any, prisma, {} as any, {} as any, {} as any, {} as any, {} as any, {} as any);

const plan = (over: Partial<Plan> = {}): Plan => ({
  id: 'p1',
  userId: 'u1',
  currency: 'SAR',
  totalAmount: 900_000, // SAR 9,000
  amountPaid: 360_000, // 40% funded
  status: 'ACTIVE',
  maturesAt: null,
  ...over,
});

describe('burial prepayment (escrow)', () => {
  it('a part-funded plan NEVER blocks cancelling the subscription', async () => {
    const plans = [plan()];
    const subs = [{ id: 's1', currentPeriodEnd: new Date('2027-01-01'), cancelAtPeriodEnd: false }];
    const s = svc(makeDb(plans, subs));

    const res = await s.cancelSubscription('u1');

    expect(res.scheduledCancellation).toBe(true);
    expect(subs[0].cancelAtPeriodEnd).toBe(true);
  });

  it('cancelling returns every unit contributed — contributions are never forfeit', async () => {
    const plans = [plan({ amountPaid: 360_000 })];
    const subs = [{ id: 's1', currentPeriodEnd: new Date(), cancelAtPeriodEnd: false }];
    const s = svc(makeDb(plans, subs));

    const res = await s.cancelSubscription('u1');

    expect(res.burialRefund).toMatchObject({ refundDueMinor: 360_000, currency: 'SAR' });
    expect(plans[0].status).toBe('CANCELLED');
    expect(plans[0].refundDueMinor).toBe(360_000);
    expect(plans[0].cancelledAt).toBeInstanceOf(Date);
  });

  it('the user can stop the plan directly, at any time', async () => {
    const plans = [plan({ amountPaid: 1_000 })];
    const s = svc(makeDb(plans));

    const res = await s.cancelBurialPlanForUser('u1', 'Cancelled by the user');

    expect(res).toMatchObject({ refundDueMinor: 1_000, currency: 'SAR' });
    expect(plans[0].status).toBe('CANCELLED');
  });

  it('reports the refundable amount without needing to cancel first', async () => {
    const s = svc(makeDb([plan({ amountPaid: 250_000 })]));
    const status = await s.burialPlanStatus('u1');
    expect(status.refundableMinor).toBe(250_000);
    expect(status.currency).toBe('SAR');
  });

  it('cancelling with no plan is a no-op, not an error', async () => {
    const subs = [{ id: 's1', currentPeriodEnd: new Date(), cancelAtPeriodEnd: false }];
    const s = svc(makeDb([], subs));
    const res = await s.cancelSubscription('u1');
    expect(res.burialRefund).toBeNull();
  });

  it('the plan is FULLY_FUNDED only when the whole price is contributed — it never self-completes', async () => {
    const plans = [plan({ amountPaid: 0 })];
    const s = svc(makeDb(plans));

    await s.recordBurialContribution('p1', 899_999); // one unit short
    expect(plans[0].status).toBe('ACTIVE');

    await s.recordBurialContribution('p1', 1);
    expect(plans[0].status).toBe('FULLY_FUNDED');
  });

  it('a cancelled plan cannot quietly take further contributions', async () => {
    const plans = [plan({ status: 'CANCELLED' })];
    const s = svc(makeDb(plans));
    await expect(s.recordBurialContribution('p1', 1000)).rejects.toThrow(BadRequestException);
  });

  describe('refund queue — money we owe must be visible', () => {
    it('lists cancelled plans with an outstanding refund, totalled per currency', async () => {
      const plans = [
        plan({ id: 'p1', userId: 'u1', status: 'CANCELLED', refundDueMinor: 100_000 }),
        plan({ id: 'p2', userId: 'u2', status: 'CANCELLED', refundDueMinor: 50_000 }),
        plan({ id: 'p3', userId: 'u3', status: 'CANCELLED', refundDueMinor: 0 }), // already settled
        plan({ id: 'p4', userId: 'u4', status: 'ACTIVE' }), // not owed anything
      ];
      const queue = await svc(makeDb(plans)).pendingBurialRefunds();

      expect(queue.count).toBe(2);
      expect(queue.totalsByCurrency).toEqual({ SAR: 150_000 });
    });

    it('settling zeroes the debt, and settling twice is a no-op', async () => {
      const plans = [plan({ status: 'CANCELLED', refundDueMinor: 100_000 })];
      const s = svc(makeDb(plans));

      const first = await s.settleBurialRefund('p1');
      expect(first).toMatchObject({ settled: true, amountMinor: 100_000, currency: 'SAR' });
      expect(plans[0].refundDueMinor).toBe(0);

      const second = await s.settleBurialRefund('p1');
      expect(second).toEqual({ settled: false, alreadySettled: true });
    });

    it('refuses to settle a plan that was never cancelled', async () => {
      const s = svc(makeDb([plan({ status: 'ACTIVE' })]));
      await expect(s.settleBurialRefund('p1')).rejects.toThrow(/cancelled plan/i);
    });
  });
});
