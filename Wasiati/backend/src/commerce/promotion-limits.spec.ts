import { Prisma, PromotionType, Region, SubscriptionTier } from '@prisma/client';
import { PromotionsService } from './promotions.service';

/**
 * A promo code that outlives its limit is a revenue leak: WASIATI30 capped at 100
 * signups must refuse the 101st, and a launch code must stop working the day the
 * launch ends. All of that logic already lived in validate() — with no test
 * pinning it. These pin it.
 *
 * The redemption counter is moved by recordRedemption(), called from
 * payments.service on payment success, so `timesRedeemed` here stands in for
 * "this many people have actually paid with this code".
 */
const basePromo = {
  id: 'promo_1',
  code: 'WASIATI30',
  type: PromotionType.PERCENT,
  value: 30,
  currency: null,
  description: '30% off your subscription',
  active: true,
  timesRedeemed: 0,
  maxRedemptions: null as number | null,
  firstTimeOnly: false,
  startsAt: null as Date | null,
  endsAt: null as Date | null,
  appliesToTiers: [] as SubscriptionTier[],
  appliesToRegions: [] as Region[],
};

function serviceWith(overrides: Partial<typeof basePromo>) {
  const promo = { ...basePromo, ...overrides };
  // Annotated: $transaction closes over `prisma`, so inference would be circular.
  const prisma: any = {
    promotion: {
      findUnique: jest.fn().mockResolvedValue(promo),
      update: jest.fn().mockResolvedValue(promo),
    },
    processedPaymentEvent: { create: jest.fn().mockResolvedValue({}) },
    // No prior purchase unless a test says otherwise — the first-time-buyer default.
    invoice: { findFirst: jest.fn().mockResolvedValue(null) },
  };
  prisma.$transaction = jest.fn(async (fn: any) => fn(prisma));
  return { svc: new PromotionsService(prisma as any), prisma, promo };
}

describe('promotion limits — redemption cap', () => {
  it('accepts a capped code that has room left', async () => {
    const { svc } = serviceWith({ maxRedemptions: 100, timesRedeemed: 99 });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
  });

  it('refuses the redemption that would exceed the cap', async () => {
    // 100 of 100 used — the 101st person must be turned away.
    const { svc } = serviceWith({ maxRedemptions: 100, timesRedeemed: 100 });
    const r = await svc.validate('WASIATI30');
    expect(r.valid).toBe(false);
    expect(r.reason).toMatch(/fully redeemed/i);
  });

  it('a cap of 1 is genuinely single-use', async () => {
    const fresh = serviceWith({ maxRedemptions: 1, timesRedeemed: 0 });
    await expect(fresh.svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
    const used = serviceWith({ maxRedemptions: 1, timesRedeemed: 1 });
    await expect(used.svc.validate('WASIATI30')).resolves.toMatchObject({ valid: false });
  });

  it('an uncapped code never exhausts', async () => {
    const { svc } = serviceWith({ maxRedemptions: null, timesRedeemed: 10_000 });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
  });
});

describe('promotion limits — date window', () => {
  const hourAgo = () => new Date(Date.now() - 3_600_000);
  const hourAhead = () => new Date(Date.now() + 3_600_000);

  it('refuses a code before its start date', async () => {
    const { svc } = serviceWith({ startsAt: hourAhead() });
    const r = await svc.validate('WASIATI30');
    expect(r.valid).toBe(false);
    expect(r.reason).toMatch(/not active yet/i);
  });

  it('refuses a code after its end date', async () => {
    const { svc } = serviceWith({ endsAt: hourAgo() });
    const r = await svc.validate('WASIATI30');
    expect(r.valid).toBe(false);
    expect(r.reason).toMatch(/expired/i);
  });

  it('accepts a code inside its window', async () => {
    const { svc } = serviceWith({ startsAt: hourAgo(), endsAt: hourAhead() });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
  });

  it('an open-ended code works with no window at all', async () => {
    const { svc } = serviceWith({ startsAt: null, endsAt: null });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
  });

  it('reports expiry even when the cap still has room', async () => {
    // Both limits are independent gates; neither masks the other.
    const { svc } = serviceWith({ endsAt: hourAgo(), maxRedemptions: 100, timesRedeemed: 0 });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: false });
  });
});

describe('promotion limits — deactivation', () => {
  it('an inactive code is refused regardless of cap or window', async () => {
    const { svc } = serviceWith({ active: false, maxRedemptions: 100, timesRedeemed: 0 });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: false });
  });
});

describe('redemption counter', () => {
  it('increments once per payment', async () => {
    const { svc, prisma } = serviceWith({ maxRedemptions: 100 });
    await svc.recordRedemption('promo_1', 'pi_123');
    expect(prisma.promotion.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { timesRedeemed: { increment: 1 } } }),
    );
  });

  it('does NOT double-count the two Stripe events for one payment', async () => {
    // checkout.session.completed AND payment_intent.succeeded both fire for one
    // paid session. Without the per-payment marker a 100-cap promo would exhaust
    // at 50 real signups.
    const { svc, prisma } = serviceWith({ maxRedemptions: 100 });
    prisma.processedPaymentEvent.create
      .mockResolvedValueOnce({})
      .mockRejectedValueOnce(
        new Prisma.PrismaClientKnownRequestError('dup', { code: 'P2002', clientVersion: 'x' }),
      );

    await svc.recordRedemption('promo_1', 'pi_123');
    await svc.recordRedemption('promo_1', 'pi_123'); // same payment, second event

    expect(prisma.promotion.update).toHaveBeenCalledTimes(1);
  });

  it('rethrows non-duplicate failures instead of silently dropping a redemption', async () => {
    const { svc, prisma } = serviceWith({});
    prisma.processedPaymentEvent.create.mockRejectedValueOnce(new Error('db down'));
    await expect(svc.recordRedemption('promo_1', 'pi_123')).rejects.toThrow(/db down/i);
  });
});

describe('archive / reinstate — deleting a promo must be reversible', () => {
  it('archive deactivates instead of destroying the row', async () => {
    // The old remove() called prisma.promotion.delete(), which was irreversible and
    // threw away timesRedeemed. A mis-click on a live code could not be undone.
    const { svc, prisma } = serviceWith({});
    await expect(svc.archive('promo_1', 'admin_1')).resolves.toMatchObject({ archived: true });
    expect(prisma.promotion.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ active: false }) }),
    );
    // The row itself must survive so it can come back.
    expect((prisma.promotion as any).delete).toBeUndefined();
  });

  it('an archived code is refused at checkout immediately', async () => {
    const { svc } = serviceWith({ active: false });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: false });
  });

  it('reinstate brings it back', async () => {
    const { svc, prisma } = serviceWith({ active: false });
    await expect(svc.reinstate('promo_1', 'admin_1')).resolves.toMatchObject({ active: true });
    expect(prisma.promotion.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ active: true }) }),
    );
  });

  it('reinstating does NOT reset the redemption counter', async () => {
    // A code capped at 100 that archived at 97 must resume at 97, not 0 — otherwise
    // archive+reinstate becomes a way to mint unlimited redemptions.
    const { svc, prisma } = serviceWith({ active: false, timesRedeemed: 97, maxRedemptions: 100 });
    await svc.reinstate('promo_1', 'admin_1');
    const data = prisma.promotion.update.mock.calls[0][0].data;
    expect(data).not.toHaveProperty('timesRedeemed');
    expect(data).not.toHaveProperty('maxRedemptions');
  });

  it('both record which admin acted, for the audit trail', async () => {
    const a = serviceWith({});
    await a.svc.archive('promo_1', 'admin_1');
    expect(a.prisma.promotion.update.mock.calls[0][0].data.updatedBy).toBe('admin_1');
    const r = serviceWith({ active: false });
    await r.svc.reinstate('promo_1', 'admin_2');
    expect(r.prisma.promotion.update.mock.calls[0][0].data.updatedBy).toBe('admin_2');
  });

  it('archiving or reinstating something that does not exist 404s', async () => {
    const { svc, prisma } = serviceWith({});
    prisma.promotion.findUnique.mockResolvedValue(null);
    await expect(svc.archive('nope', 'admin_1')).rejects.toThrow(/not found/i);
    await expect(svc.reinstate('nope', 'admin_1')).rejects.toThrow(/not found/i);
  });
});

/**
 * A limit that can be set but never removed is a trap: the Edit dialog's "clear"
 * buttons send an explicit null, and update() must pass that through to the DB as a
 * clear — while an ABSENT field must remain "leave unchanged". The service used to
 * collapse a null startsAt/endsAt into undefined, so a date window, once set, was
 * permanent through the API.
 */
describe('update — clearing limits with an explicit null', () => {
  it('null endsAt CLEARS the expiry instead of silently keeping it', async () => {
    const { svc, prisma } = serviceWith({ endsAt: new Date('2026-08-01T00:00:00Z') });
    await svc.update('promo_1', { endsAt: null }, 'admin_1');
    const data = prisma.promotion.update.mock.calls[0][0].data;
    expect(data.endsAt).toBeNull();
  });

  it('null startsAt and null maxRedemptions clear likewise', async () => {
    const { svc, prisma } = serviceWith({ startsAt: new Date(), maxRedemptions: 100 });
    await svc.update('promo_1', { startsAt: null, maxRedemptions: null }, 'admin_1');
    const data = prisma.promotion.update.mock.calls[0][0].data;
    expect(data.startsAt).toBeNull();
    expect(data.maxRedemptions).toBeNull();
  });

  it('an ABSENT field stays undefined — a partial edit must not clear what it never mentioned', async () => {
    const { svc, prisma } = serviceWith({ endsAt: new Date('2026-08-01T00:00:00Z'), maxRedemptions: 100 });
    await svc.update('promo_1', { value: 20 }, 'admin_1');
    const data = prisma.promotion.update.mock.calls[0][0].data;
    // undefined, not null: Prisma reads undefined as "no change" and null as "set NULL".
    expect(data.endsAt).toBeUndefined();
    expect(data.startsAt).toBeUndefined();
    expect(data.maxRedemptions).toBeUndefined();
  });

  it('a supplied ISO date still lands as a Date', async () => {
    const { svc, prisma } = serviceWith({});
    await svc.update('promo_1', { endsAt: '2026-09-01T23:59:59Z' }, 'admin_1');
    const data = prisma.promotion.update.mock.calls[0][0].data;
    expect(data.endsAt).toEqual(new Date('2026-09-01T23:59:59Z'));
  });
});

/**
 * firstTimeOnly used to be a dead column: accepted by the DTO, written on create, and read
 * by NOTHING — validate() took no user identity, so it could not enforce it even in
 * principle. An admin could set it, see it saved, and hand every returning customer the
 * discount anyway. LAUNCH25 is seeded with it true, no cap and no expiry, so the leak was
 * unbounded. These pin the enforcement.
 */
describe('firstTimeOnly', () => {
  it('refuses a customer who has purchased before', async () => {
    const { svc, prisma } = serviceWith({ firstTimeOnly: true });
    prisma.invoice.findFirst.mockResolvedValue({ id: 'inv_1' });
    const r = await svc.validate('WASIATI30', undefined, undefined, 'user_1');
    expect(r.valid).toBe(false);
    expect(r.reason).toMatch(/first subscription/i);
  });

  it('allows a genuine first-time customer', async () => {
    const { svc, prisma } = serviceWith({ firstTimeOnly: true });
    prisma.invoice.findFirst.mockResolvedValue(null);
    await expect(svc.validate('WASIATI30', undefined, undefined, 'user_1')).resolves.toMatchObject({
      valid: true,
    });
  });

  it('a REFUNDED purchase still counts — buy/refund/rebuy cannot farm the code', async () => {
    // Invoice rows survive a refund (status REFUNDED), and findFirst does not filter on
    // status precisely so that a refunded buyer is not laundered back into "first time".
    const { svc, prisma } = serviceWith({ firstTimeOnly: true });
    prisma.invoice.findFirst.mockResolvedValue({ id: 'inv_refunded' });
    await expect(svc.validate('WASIATI30', undefined, undefined, 'user_1')).resolves.toMatchObject({
      valid: false,
    });
  });

  it('previews optimistically for an anonymous visitor', async () => {
    // The pricing page has no user. Telling a first-time visitor their launch code is
    // invalid would be both wrong and a reason not to sign up — and it cannot become an
    // unearned discount, because applyToAmount always has a user.
    const { svc } = serviceWith({ firstTimeOnly: true });
    await expect(svc.validate('WASIATI30')).resolves.toMatchObject({ valid: true });
  });

  it('does not touch invoices at all when the code is not firstTimeOnly', async () => {
    const { svc, prisma } = serviceWith({ firstTimeOnly: false });
    await svc.validate('WASIATI30', undefined, undefined, 'user_1');
    expect(prisma.invoice.findFirst).not.toHaveBeenCalled();
  });

  it('applyToAmount REQUIRES a userId, so no call site can skip the check', () => {
    // (code, plan, userId) — an optional argument would let a new caller silently
    // bypass enforcement, which is exactly how this became a dead column.
    expect(PromotionsService.prototype.applyToAmount.length).toBe(3);
  });
});
