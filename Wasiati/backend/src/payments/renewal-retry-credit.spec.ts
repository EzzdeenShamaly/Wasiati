import { Region, SubscriptionTier } from '@prisma/client';
import { SubscriptionsService } from './subscriptions.service';

/**
 * A subscriber with account credit and a failing card must keep being retried.
 *
 * THE WEDGE THIS PINS: the credit consume keyed on the renewal PERIOD
 * (`${sub.id}:${currentPeriodEnd}`), and AccountCredit is unique on
 * (sourceType, sourceId, userId).
 *
 *   day 1  consume('Renewal', periodId) debits; the card declines; the credit is
 *          granted back under 'RenewalFailed'; markFailed sets PAST_DUE.
 *   day 2  the period has NOT advanced, so the SAME periodId is computed and the same
 *          debit row is attempted → P2002, thrown BEFORE chargeStoredInstrument and
 *          before markFailed. runBillingCycle's catch only logs it.
 *
 * So the card was never retried, failedPaymentCount never advanced, dunning never
 * escalated, and the subscription never renewed or cancelled — wedged forever, crashing
 * nightly, in silence. It required credit AND a failing card together, which is why the
 * existing renewal tests (credit-only, or charge-approves) never saw it.
 *
 * The ledger mock below enforces the REAL unique constraint. Without that enforcement
 * these tests pass against the broken code, which is the whole point.
 */
describe('renewal retries with account credit', () => {
  const plan = {
    id: 'p1',
    tier: SubscriptionTier.PREMIUM,
    interval: 'MONTH',
    region: Region.US,
    displayName: 'Premium',
    unitAmount: 1900,
    currency: 'USD',
    active: true,
  };

  /** Mirrors AccountCredit's @@unique([sourceType, sourceId, userId]). */
  function ledger() {
    const keys = new Set<string>();
    const debits: any[] = [];
    const grants: any[] = [];
    return {
      debits,
      grants,
      consume: async (p: any) => {
        const key = `${p.sourceType}|${p.sourceId}|${p.userId}`;
        if (keys.has(key)) {
          const err: any = new Error('Unique constraint failed');
          err.code = 'P2002';
          throw err;
        }
        keys.add(key);
        debits.push(p);
        return p.requestedMinor > 400 ? 400 : p.requestedMinor; // $4 of credit available
      },
      grant: async (p: any) => {
        grants.push(p);
        return { granted: true };
      },
    };
  }

  /** A card that always declines, and a subscription that stays due. */
  function makeDeclining() {
    const credits = ledger();
    const charges: any[] = [];
    const updates: any[] = [];
    // Mutable so markFailed's write is visible to the next run, exactly like the DB.
    const sub: any = {
      id: 's1',
      userId: 'u1',
      tier: SubscriptionTier.PREMIUM,
      interval: 'MONTH',
      status: 'ACTIVE',
      currentPeriodEnd: new Date('2026-07-01T00:00:00Z'),
      cancelAtPeriodEnd: false,
      paymentInstrumentId: 'cus_1|pm_1',
      failedPaymentCount: 0,
    };
    const prisma: any = {
      subscription: {
        findMany: async () => [{ ...sub }],
        update: async ({ data }: any) => {
          updates.push(data);
          Object.assign(sub, data); // the period does NOT advance on failure
          return sub;
        },
      },
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findFirst: async () => plan },
    };
    const provider: any = {
      chargeStoredInstrument: async (req: any) => {
        charges.push(req);
        return { approved: false, declineReason: 'card_declined' };
      },
    };
    const notifications: any = { sendEmail: async () => true, sendSms: async () => true };
    const svc = new SubscriptionsService(prisma, notifications, credits as any, { record: async () => {} } as any, provider);
    return { svc, credits, charges, updates, sub };
  }

  it('retries the card on the NEXT run instead of crashing on the ledger key', async () => {
    const { svc, charges } = makeDeclining();

    await svc.runBillingCycle(new Date('2026-07-02T04:00:00Z'));
    expect(charges).toHaveLength(1);

    // The wedge: this second run used to throw P2002 inside consume, before the charge.
    await svc.runBillingCycle(new Date('2026-07-03T04:00:00Z'));
    expect(charges).toHaveLength(2);
  });

  it('advances dunning on every retry, so a dead card eventually cancels', async () => {
    const { svc, sub } = makeDeclining();

    await svc.runBillingCycle(new Date('2026-07-02T04:00:00Z'));
    expect(sub.failedPaymentCount).toBe(1);

    await svc.runBillingCycle(new Date('2026-07-03T04:00:00Z'));
    expect(sub.failedPaymentCount).toBe(2);

    // Previously it stuck at 1 forever: PAST_DUE, never charged, never cancelled.
    expect(sub.status).not.toBe('ACTIVE');
  });

  it('each attempt writes its OWN debit, so credit is never double-spent', async () => {
    const { svc, credits } = makeDeclining();

    await svc.runBillingCycle(new Date('2026-07-02T04:00:00Z'));
    await svc.runBillingCycle(new Date('2026-07-03T04:00:00Z'));

    expect(credits.debits).toHaveLength(2);
    const [first, second] = credits.debits;
    expect(first.sourceId).not.toBe(second.sourceId);
    // Same period, different attempt — the period is still the invoice's key.
    expect(first.sourceId).toContain('2026-07-01T00:00:00.000Z');
    expect(second.sourceId).toContain('2026-07-01T00:00:00.000Z');
  });

  it('returns the credit after each failed attempt, paired to that attempt', async () => {
    const { svc, credits } = makeDeclining();

    await svc.runBillingCycle(new Date('2026-07-02T04:00:00Z'));
    await svc.runBillingCycle(new Date('2026-07-03T04:00:00Z'));

    // Every debit has a matching reversal, so the ledger nets to zero while the card
    // keeps failing — the customer is never quietly out of pocket.
    expect(credits.grants).toHaveLength(2);
    expect(credits.grants.map((g: any) => g.sourceId)).toEqual(credits.debits.map((d: any) => d.sourceId));
    expect(credits.grants.every((g: any) => g.amountMinor === 400)).toBe(true);
  });

  it('a TRUE concurrent double-run still collides — that protection is intended', async () => {
    // Two workers reading the same failedPaymentCount before either markFailed lands
    // must not both spend the credit. P2002 is the right answer there; it is only
    // wrong when it repeats every night, which the attempt key fixes.
    const credits = ledger();
    const p = { userId: 'u1', requestedMinor: 1900, currency: 'USD', sourceType: 'Renewal', sourceId: 's1:period:a0' };
    await expect(credits.consume(p)).resolves.toBe(400);
    await expect(credits.consume(p)).rejects.toMatchObject({ code: 'P2002' });
  });
});
