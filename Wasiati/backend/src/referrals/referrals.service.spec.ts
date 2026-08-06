import { BadRequestException, NotFoundException } from '@nestjs/common';
import { REFERRAL_HOLD_DAYS, REFERRED_DISCOUNT_PERCENT, ReferralsService } from './referrals.service';

/**
 * The referral rules decide who gets paid, so they are tested directly against a
 * hand-rolled in-memory Prisma double rather than mocks-of-mocks.
 */
type Ref = {
  id: string;
  referrerId: string;
  referredUserId: string;
  code: string;
  status: string;
  rewardYear?: number | null;
  qualifyingEvent?: string | null;
  referrerRewardBasisMinor?: number | null;
  referrerRewardMinor?: number | null;
  referrerRewardCurrency?: string | null;
  referrerRewardMaturesAt?: Date | null;
  referredDiscountPercent?: number | null;
  rejectedReason?: string | null;
};

function makeDb() {
  const users = new Map<string, { id: string; email: string; region: string }>();
  const codes = new Map<string, { userId: string; code: string }>(); // code -> owner
  const referrals: Ref[] = [];
  const subscriptions: { userId: string }[] = [];
  let seq = 0;

  const referralApi = {
    findUnique: async ({ where }: any) =>
      referrals.find((r) => (where.referredUserId ? r.referredUserId === where.referredUserId : r.id === where.id)) ??
      null,
    findMany: async ({ where }: any) =>
      referrals.filter((r) => (where?.referrerId ? r.referrerId === where.referrerId : true)),
    count: async ({ where }: any) =>
      referrals.filter((r) => r.status === where.status && r.rewardYear === where.rewardYear).length,
    aggregate: async ({ where }: any) => ({
      _sum: {
        referrerRewardMinor: referrals
          .filter(
            (r) =>
              r.referrerId === where.referrerId && r.status === where.status && r.rewardYear === where.rewardYear,
          )
          .reduce((s, r) => s + (r.referrerRewardMinor ?? 0), 0),
      },
    }),
    create: async ({ data }: any) => {
      const r: Ref = { id: `ref${++seq}`, ...data };
      referrals.push(r);
      return r;
    },
    update: async ({ where, data }: any) => {
      const r = referrals.find((x) => x.id === where.id)!;
      Object.assign(r, data);
      return r;
    },
  };

  const prisma: any = {
    user: { findUnique: async ({ where }: any) => users.get(where.id) ?? null },
    referralCode: {
      findUnique: async ({ where }: any) =>
        where.code ? (codes.get(where.code) ?? null) : ([...codes.values()].find((c) => c.userId === where.userId) ?? null),
      create: async ({ data }: any) => {
        if (codes.has(data.code)) throw new Error('unique');
        codes.set(data.code, data);
        return data;
      },
    },
    referral: referralApi,
    subscription: { findFirst: async ({ where }: any) => subscriptions.find((s) => s.userId === where.userId) ?? null },
    $transaction: async (fn: any) => fn({ referral: referralApi }),
  };

  return { prisma, users, codes, referrals, subscriptions };
}

const config = (cap?: number) => ({ get: (k: string) => (k === 'REFERRAL_YEARLY_CAP' ? cap : undefined) }) as any;

/** Records what the ledger was asked to do, so we can assert on credit movement. */
function makeCredits() {
  const granted: any[] = [];
  const reversed: any[] = [];
  const svc: any = {
    grant: async (p: any) => { granted.push(p); return { granted: true }; },
    reverse: async (p: any) => { reversed.push(p); return { reversed: true }; },
    consume: async () => 0,
    balance: async () => 0,
    balances: async () => ({ spendableMinor: 0, pendingMinor: 0, totalMinor: 0 }),
  };
  return { svc, granted, reversed };
}

describe('ReferralsService', () => {
  const YEAR_OLD_ENV = { ...process.env };
  afterEach(() => {
    process.env = { ...YEAR_OLD_ENV };
  });

  describe('isQualifying', () => {
    it('annual and one-time qualify; monthly does not', () => {
      expect(ReferralsService.isQualifying('YEAR' as any)).toBe(true);
      expect(ReferralsService.isQualifying('ONE_TIME' as any)).toBe(true);
      expect(ReferralsService.isQualifying('MONTH' as any)).toBe(false);
    });
  });

  describe('commissionMinor — 2.5% of first-year value', () => {
    it('takes 2.5% and rounds DOWN, never up', () => {
      expect(ReferralsService.commissionMinor(19_000)).toBe(475); // SAR 190.00 -> SAR 4.75
      expect(ReferralsService.commissionMinor(34_900)).toBe(872); // SAR 349.00 -> SAR 8.72 (872.5 floored)
      expect(ReferralsService.commissionMinor(64_900)).toBe(1622); // SAR 649.00 -> SAR 16.22
    });

    it('never returns a negative commission', () => {
      expect(ReferralsService.commissionMinor(-100)).toBe(0);
      expect(ReferralsService.commissionMinor(0)).toBe(0);
    });
  });

  describe('claim', () => {
    it('rejects self-referral', async () => {
      const db = makeDb();
      db.users.set('u1', { id: 'u1', email: 'a@x.com', region: 'US' });
      db.codes.set('ABC12345', { userId: 'u1', code: 'ABC12345' });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      await expect(svc.claim('u1', 'abc12345')).rejects.toThrow(BadRequestException);
    });

    it('rejects an unknown code', async () => {
      const db = makeDb();
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      await expect(svc.claim('u2', 'NOPE0000')).rejects.toThrow(NotFoundException);
    });

    it('rejects a second referral for the same user', async () => {
      const db = makeDb();
      db.codes.set('ABC12345', { userId: 'u1', code: 'ABC12345' });
      db.referrals.push({ id: 'r0', referrerId: 'u1', referredUserId: 'u2', code: 'ABC12345', status: 'PENDING' });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      await expect(svc.claim('u2', 'ABC12345')).rejects.toThrow(/already used a referral code/);
    });

    it('rejects a code applied after the first purchase', async () => {
      const db = makeDb();
      db.codes.set('ABC12345', { userId: 'u1', code: 'ABC12345' });
      db.subscriptions.push({ userId: 'u2' });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      await expect(svc.claim('u2', 'ABC12345')).rejects.toThrow(/before your first purchase/);
    });

    it('creates a PENDING referral carrying the friend’s 10% discount', async () => {
      const db = makeDb();
      db.codes.set('ABC12345', { userId: 'u1', code: 'ABC12345' });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const r = await svc.claim('u2', 'abc12345');
      expect(r.status).toBe('PENDING');
      expect(r.referrerId).toBe('u1');
      expect(r.referredDiscountPercent).toBe(REFERRED_DISCOUNT_PERCENT);
    });
  });

  describe('pendingDiscountPercent — the friend’s 10% off', () => {
    const seedPending = (db: ReturnType<typeof makeDb>) =>
      db.referrals.push({ id: 'r1', referrerId: 'u1', referredUserId: 'u2', code: 'C', status: 'PENDING' });

    it('gives 10% off an annual or one-time plan', async () => {
      const db = makeDb();
      seedPending(db);
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      expect(await svc.pendingDiscountPercent('u2', 'YEAR' as any)).toBe(10);
      expect(await svc.pendingDiscountPercent('u2', 'ONE_TIME' as any)).toBe(10);
    });

    it('gives NOTHING on monthly — the discount requires a one-year commitment', async () => {
      const db = makeDb();
      seedPending(db);
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      expect(await svc.pendingDiscountPercent('u2', 'MONTH' as any)).toBe(0);
    });

    it('gives nothing to a user who was never referred, or who already used it', async () => {
      const db = makeDb();
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      expect(await svc.pendingDiscountPercent('u9', 'YEAR' as any)).toBe(0);

      db.referrals.push({ id: 'r2', referrerId: 'u1', referredUserId: 'u3', code: 'C', status: 'REWARDED' });
      expect(await svc.pendingDiscountPercent('u3', 'YEAR' as any)).toBe(0);
    });
  });

  describe('handleQualifyingPurchase', () => {
    const seed = (db: ReturnType<typeof makeDb>, region = 'US') => {
      // Referrer and referred are ALWAYS in the same region — regions are separate
      // databases, so a cross-region referral row cannot exist.
      db.users.set('u1', { id: 'u1', email: 'r@x.com', region });
      db.users.set('u2', { id: 'u2', email: 'd@x.com', region });
      db.referrals.push({ id: 'r1', referrerId: 'u1', referredUserId: 'u2', code: 'C', status: 'PENDING' });
    };

    it('a monthly subscription does NOT qualify', async () => {
      const db = makeDb();
      seed(db);
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'MONTH' as any, tier: 'STANDARD' as any, basisMinor: 1900, currency: 'USD',
      });
      expect(res.outcome).toBe('not-qualifying');
      expect(res.grants).toHaveLength(0);
      expect(db.referrals[0].status).toBe('PENDING');
    });

    it('pays the referrer 2.5% of the first-year value — and the friend NO credit', async () => {
      const db = makeDb();
      seed(db);
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(), credits.svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 20_000, currency: 'USD',
      });

      expect(res.outcome).toBe('rewarded');
      // Only ONE grant: the friend's benefit was a discount at checkout.
      expect(res.grants).toHaveLength(1);
      expect(res.grants[0]).toMatchObject({ userId: 'u1', amountMinor: 500, currency: 'USD' });
      expect(credits.granted).toHaveLength(1);
      expect(credits.granted[0].userId).toBe('u1');

      expect(db.referrals[0].status).toBe('REWARDED');
      expect(db.referrals[0].qualifyingEvent).toBe('ANNUAL_SUBSCRIPTION');
      expect(db.referrals[0].referrerRewardBasisMinor).toBe(20_000);
    });

    it('HOLDS the commission for 100 days before it is spendable', async () => {
      const db = makeDb();
      seed(db);
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(), credits.svc);
      const before = Date.now();
      await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'ONE_TIME' as any, tier: 'BASIC' as any, basisMinor: 34_900, currency: 'USD',
      });

      const maturesAt: Date = credits.granted[0].maturesAt;
      expect(maturesAt).toBeInstanceOf(Date);
      const days = (maturesAt.getTime() - before) / (24 * 60 * 60 * 1000);
      expect(days).toBeGreaterThan(REFERRAL_HOLD_DAYS - 0.01);
      expect(days).toBeLessThan(REFERRAL_HOLD_DAYS + 0.01);
      expect(db.referrals[0].referrerRewardMaturesAt).toEqual(maturesAt);
    });

    it('a one-time purchase qualifies', async () => {
      const db = makeDb();
      seed(db);
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'ONE_TIME' as any, tier: 'BASIC' as any, basisMinor: 34_900, currency: 'USD',
      });
      expect(res.outcome).toBe('rewarded');
      expect(res.grants[0].amountMinor).toBe(872);
      expect(db.referrals[0].qualifyingEvent).toBe('ONE_TIME');
    });

    it('pays a Saudi referrer in SAR', async () => {
      const db = makeDb();
      seed(db, 'KSA');
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 46_800, currency: 'SAR',
      });
      expect(res.grants[0]).toMatchObject({ userId: 'u1', amountMinor: 1170, currency: 'SAR' });
    });

    it('is idempotent — an already-rewarded referral is skipped', async () => {
      const db = makeDb();
      seed(db);
      db.referrals[0].status = 'REWARDED';
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 20_000, currency: 'USD',
      });
      expect(res.outcome).toBe('skipped');
      expect(res.grants).toHaveLength(0);
    });

    it('marks CAPPED (and grants nothing) once the PROGRAMME cap is reached', async () => {
      const db = makeDb();
      seed(db);
      const year = new Date().getUTCFullYear();
      db.referrals.push(
        { id: 'x1', referrerId: 'z', referredUserId: 'z1', code: 'C', status: 'REWARDED', rewardYear: year },
        { id: 'x2', referrerId: 'z', referredUserId: 'z2', code: 'C', status: 'REWARDED', rewardYear: year },
      );
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(2), credits.svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 20_000, currency: 'USD',
      });
      expect(res.outcome).toBe('capped');
      expect(credits.granted).toHaveLength(0);
      expect(db.referrals[0].status).toBe('CAPPED'); // recorded, never silently dropped
      expect(db.referrals[0].referrerRewardBasisMinor).toBe(20_000); // reviewable later
    });

    it('trims the commission to the referrer’s $500 yearly ceiling', async () => {
      const db = makeDb();
      seed(db);
      const year = new Date().getUTCFullYear();
      // u1 has already earned $499 this year; cap is $500.
      db.referrals.push({
        id: 'x1', referrerId: 'u1', referredUserId: 'z1', code: 'C',
        status: 'REWARDED', rewardYear: year, referrerRewardMinor: 49_900,
      });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 100_000, currency: 'USD',
      });
      // 2.5% of $1000 = $25, but only $1 of headroom remains.
      expect(res.outcome).toBe('rewarded');
      expect(res.grants[0].amountMinor).toBe(100);
    });

    it('pays NOTHING once the referrer’s $500 ceiling is exhausted', async () => {
      const db = makeDb();
      seed(db);
      const year = new Date().getUTCFullYear();
      db.referrals.push({
        id: 'x1', referrerId: 'u1', referredUserId: 'z1', code: 'C',
        status: 'REWARDED', rewardYear: year, referrerRewardMinor: 50_000, // exactly $500
      });
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(), credits.svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 100_000, currency: 'USD',
      });
      expect(res.outcome).toBe('capped');
      expect(credits.granted).toHaveLength(0);
      expect(db.referrals[0].status).toBe('CAPPED');
    });

    it('the ceiling is per-referrer, not global — another referrer is unaffected', async () => {
      const db = makeDb();
      seed(db);
      const year = new Date().getUTCFullYear();
      db.referrals.push({
        id: 'x1', referrerId: 'someone-else', referredUserId: 'z1', code: 'C',
        status: 'REWARDED', rewardYear: year, referrerRewardMinor: 50_000,
      });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u2', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 20_000, currency: 'USD',
      });
      expect(res.outcome).toBe('rewarded');
      expect(res.grants[0].amountMinor).toBe(500);
    });

    it('does nothing when the buyer was never referred', async () => {
      const db = makeDb();
      db.users.set('u9', { id: 'u9', email: 'x@x.com', region: 'US' });
      const svc = new ReferralsService(db.prisma, config(), makeCredits().svc);
      const res = await svc.handleQualifyingPurchase({
        userId: 'u9', interval: 'YEAR' as any, tier: 'PREMIUM' as any, basisMinor: 20_000, currency: 'USD',
      });
      expect(res.outcome).toBe('skipped');
    });
  });

  describe('rejectForRefund', () => {
    it('flips a rewarded referral to REJECTED and reverses ONLY the referrer’s credit', async () => {
      const db = makeDb();
      db.referrals.push({
        id: 'r1', referrerId: 'u1', referredUserId: 'u2', code: 'C', status: 'REWARDED',
        referrerRewardMinor: 500, referrerRewardCurrency: 'USD',
      });
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(), credits.svc);
      await svc.rejectForRefund('u2');

      expect(db.referrals[0].status).toBe('REJECTED');
      // The friend got a discount, not credit — there is nothing to claw back.
      expect(credits.reversed).toHaveLength(1);
      expect(credits.reversed[0]).toMatchObject({ userId: 'u1', amountMinor: 500, currency: 'USD' });
    });

    it('reverses nothing for a referral that was only CAPPED', async () => {
      const db = makeDb();
      db.referrals.push({ id: 'r1', referrerId: 'u1', referredUserId: 'u2', code: 'C', status: 'CAPPED' });
      const credits = makeCredits();
      const svc = new ReferralsService(db.prisma, config(), credits.svc);
      await svc.rejectForRefund('u2');
      expect(db.referrals[0].status).toBe('REJECTED');
      expect(credits.reversed).toHaveLength(0);
    });
  });
});
