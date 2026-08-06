import { CreditReason, Prisma } from '@prisma/client';
import { CreditsService } from './credits.service';

/** The real Prisma error the service catches, so the test exercises the real path. */
const uniqueViolation = () =>
  new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
    code: 'P2002',
    clientVersion: 'test',
  });

/**
 * The ledger moves real money, so it is tested against an in-memory double of the
 * Prisma calls it actually makes, including the unique-constraint behaviour that
 * provides idempotency.
 */
function makeDb() {
  type Row = {
    userId: string;
    amountMinor: number;
    currency: string;
    reason: string;
    sourceType?: string | null;
    sourceId?: string | null;
    maturesAt?: Date | null;
  };
  const rows: Row[] = [];

  const uniqueKey = (r: Row) =>
    r.sourceType == null || r.sourceId == null ? null : `${r.sourceType}|${r.sourceId}|${r.userId}`;

  /**
   * Honours the maturation filters the service actually sends. Without this the
   * double would sum held credit as if it were spendable and the hold would look
   * like it worked when it did not.
   */
  const matches = (r: Row, where: any): boolean => {
    if (r.userId !== where.userId || r.currency !== where.currency) return false;
    if (where.maturesAt?.gt) return r.maturesAt != null && r.maturesAt > where.maturesAt.gt;
    if (where.OR) {
      return where.OR.some((clause: any) =>
        'maturesAt' in clause && clause.maturesAt === null
          ? r.maturesAt == null
          : r.maturesAt != null && r.maturesAt <= clause.maturesAt.lte,
      );
    }
    return true;
  };

  const api = {
    aggregate: async ({ where }: any) => ({
      _sum: {
        amountMinor: rows.filter((r) => matches(r, where)).reduce((s, r) => s + r.amountMinor, 0),
      },
    }),
    create: async ({ data }: any) => {
      const key = uniqueKey(data);
      if (key && rows.some((r) => uniqueKey(r) === key)) throw uniqueViolation();
      rows.push(data);
      return data;
    },
    findMany: async () => rows,
  };

  const prisma: any = {
    accountCredit: api,
    $transaction: async (fn: any) => fn({ accountCredit: api }),
  };
  return { prisma, rows };
}

describe('CreditsService', () => {
  it('grants credit and reports the balance', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    await svc.grant({ userId: 'u1', amountMinor: 500, currency: 'usd', reason: CreditReason.REFERRAL_REWARD });
    expect(await svc.balance('u1', 'USD')).toBe(500);
  });

  it('is idempotent on (sourceType, sourceId, user) — a replayed webhook cannot double-credit', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    const grant = () =>
      svc.grant({
        userId: 'u1',
        amountMinor: 500,
        currency: 'USD',
        reason: CreditReason.REFERRAL_REWARD,
        sourceType: 'Referral',
        sourceId: 'r1',
      });

    expect(await grant()).toEqual({ granted: true });
    expect(await grant()).toEqual({ granted: false }); // replay
    expect(await svc.balance('u1', 'USD')).toBe(500); // not 1000
  });

  it('grant() ignores a negative amount rather than silently removing credit', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    await svc.grant({ userId: 'u1', amountMinor: -500, currency: 'USD', reason: CreditReason.REFERRAL_REWARD });
    expect(await svc.balance('u1', 'USD')).toBe(500); // abs() applied — still a credit
  });

  it('reverse() removes credit and can drive the balance negative', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    await svc.grant({ userId: 'u1', amountMinor: 500, currency: 'USD', reason: CreditReason.REFERRAL_REWARD });
    await svc.reverse({ userId: 'u1', amountMinor: 800, currency: 'USD' });
    expect(await svc.balance('u1', 'USD')).toBe(-300);
  });

  it('consume() never spends more than the balance', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    await svc.grant({ userId: 'u1', amountMinor: 300, currency: 'USD', reason: CreditReason.REFERRAL_REWARD });

    const applied = await svc.consume({ userId: 'u1', requestedMinor: 1000, currency: 'USD' });
    expect(applied).toBe(300);
    expect(await svc.balance('u1', 'USD')).toBe(0);
  });

  it('consume() returns 0 when there is no credit', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    expect(await svc.consume({ userId: 'u1', requestedMinor: 500, currency: 'USD' })).toBe(0);
    expect(await svc.balance('u1', 'USD')).toBe(0);
  });

  it('keeps currencies separate — SAR credit cannot pay a USD bill', async () => {
    const db = makeDb();
    const svc = new CreditsService(db.prisma);
    await svc.grant({ userId: 'u1', amountMinor: 1900, currency: 'SAR', reason: CreditReason.REFERRAL_REWARD });

    expect(await svc.balance('u1', 'USD')).toBe(0);
    expect(await svc.consume({ userId: 'u1', requestedMinor: 500, currency: 'USD' })).toBe(0);
    expect(await svc.balance('u1', 'SAR')).toBe(1900);
  });

  describe('maturation — referral commission is held before it can be spent', () => {
    const days = (n: number) => new Date(Date.now() + n * 24 * 60 * 60 * 1000);

    it('held credit is VISIBLE but NOT spendable', async () => {
      const db = makeDb();
      const svc = new CreditsService(db.prisma);
      await svc.grant({
        userId: 'u1', amountMinor: 500, currency: 'USD',
        reason: CreditReason.REFERRAL_REWARD, maturesAt: days(100),
      });

      expect(await svc.balance('u1', 'USD')).toBe(0); // cannot spend it
      expect(await svc.pendingBalance('u1', 'USD')).toBe(500); // but can see it
      expect(await svc.balances('u1', 'USD')).toEqual({
        spendableMinor: 0, pendingMinor: 500, totalMinor: 500,
      });
    });

    it('consume() REFUSES to spend held credit', async () => {
      const db = makeDb();
      const svc = new CreditsService(db.prisma);
      await svc.grant({
        userId: 'u1', amountMinor: 5000, currency: 'USD',
        reason: CreditReason.REFERRAL_REWARD, maturesAt: days(100),
      });
      expect(await svc.consume({ userId: 'u1', requestedMinor: 5000, currency: 'USD' })).toBe(0);
    });

    it('credit becomes spendable once the hold has expired', async () => {
      const db = makeDb();
      const svc = new CreditsService(db.prisma);
      await svc.grant({
        userId: 'u1', amountMinor: 500, currency: 'USD',
        reason: CreditReason.REFERRAL_REWARD, maturesAt: days(-1), // matured yesterday
      });

      expect(await svc.balance('u1', 'USD')).toBe(500);
      expect(await svc.pendingBalance('u1', 'USD')).toBe(0);
      expect(await svc.consume({ userId: 'u1', requestedMinor: 500, currency: 'USD' })).toBe(500);
    });

    it('spends matured credit while leaving held credit untouched', async () => {
      const db = makeDb();
      const svc = new CreditsService(db.prisma);
      await svc.grant({
        userId: 'u1', amountMinor: 300, currency: 'USD',
        reason: CreditReason.MANUAL_ADJUSTMENT, sourceType: 'a', sourceId: '1',
      }); // no hold
      await svc.grant({
        userId: 'u1', amountMinor: 500, currency: 'USD',
        reason: CreditReason.REFERRAL_REWARD, sourceType: 'b', sourceId: '2', maturesAt: days(100),
      });

      // Asks for 800, only the 300 that has matured may be spent.
      expect(await svc.consume({ userId: 'u1', requestedMinor: 800, currency: 'USD' })).toBe(300);
      expect(await svc.balance('u1', 'USD')).toBe(0);
      expect(await svc.pendingBalance('u1', 'USD')).toBe(500);
    });

    it('a grant with no maturesAt is spendable immediately', async () => {
      const db = makeDb();
      const svc = new CreditsService(db.prisma);
      await svc.grant({ userId: 'u1', amountMinor: 500, currency: 'USD', reason: CreditReason.MANUAL_ADJUSTMENT });
      expect(await svc.balance('u1', 'USD')).toBe(500);
      expect(await svc.pendingBalance('u1', 'USD')).toBe(0);
    });
  });
});
