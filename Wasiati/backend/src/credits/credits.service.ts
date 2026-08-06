import { Injectable, Logger } from '@nestjs/common';
import { CreditReason, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Internal account-credit ledger.
 *
 * The payment provider has no customer-balance primitive, so credit lives here.
 * Append-only: a balance is the SUM of its rows, never a
 * mutable field, so we can always explain how a balance came to be.
 *
 * Sign convention: positive = credit granted, negative = credit consumed.
 * Credits are held per-currency and are only ever spent against the same currency.
 *
 * Maturation: a grant may carry `maturesAt`. Until then the credit is VISIBLE but
 * not SPENDABLE — referral commission is held for 100 days so a refunded purchase
 * can be clawed back before the money is spent. Debits never have a maturesAt, so
 * they always count against the spendable balance.
 */
@Injectable()
export class CreditsService {
  private readonly logger = new Logger(CreditsService.name);

  constructor(private prisma: PrismaService) {}

  /** Rows that may be spent right now: matured grants, plus every debit. */
  private static spendableWhere(userId: string, currency: string, now: Date) {
    return {
      userId,
      currency,
      OR: [{ maturesAt: null }, { maturesAt: { lte: now } }],
    };
  }

  /** Balance the user may actually spend, in MINOR units. */
  async balance(userId: string, currency: string, now = new Date()): Promise<number> {
    const agg = await this.prisma.accountCredit.aggregate({
      where: CreditsService.spendableWhere(userId, currency.toUpperCase(), now),
      _sum: { amountMinor: true },
    });
    return agg._sum.amountMinor ?? 0;
  }

  /** Credit earned but still inside its hold window — shown, not spendable. */
  async pendingBalance(userId: string, currency: string, now = new Date()): Promise<number> {
    const agg = await this.prisma.accountCredit.aggregate({
      where: { userId, currency: currency.toUpperCase(), maturesAt: { gt: now } },
      _sum: { amountMinor: true },
    });
    return agg._sum.amountMinor ?? 0;
  }

  /** What the credit panel shows: spendable now, held, and the sum of both. */
  async balances(userId: string, currency: string, now = new Date()) {
    const [spendableMinor, pendingMinor] = await Promise.all([
      this.balance(userId, currency, now),
      this.pendingBalance(userId, currency, now),
    ]);
    return { spendableMinor, pendingMinor, totalMinor: spendableMinor + pendingMinor };
  }

  /**
   * Grants credit. Idempotent on (sourceType, sourceId, userId) — replaying a
   * webhook can never double-credit the same referral.
   */
  async grant(params: {
    userId: string;
    amountMinor: number;
    currency: string;
    reason: CreditReason;
    description?: string;
    sourceType?: string;
    sourceId?: string;
    /** Omit for immediately-spendable credit. */
    maturesAt?: Date;
  }): Promise<{ granted: boolean }> {
    const amountMinor = Math.abs(params.amountMinor);
    if (amountMinor === 0) return { granted: false };

    try {
      await this.prisma.accountCredit.create({
        data: {
          userId: params.userId,
          amountMinor,
          currency: params.currency.toUpperCase(),
          reason: params.reason,
          description: params.description,
          sourceType: params.sourceType,
          sourceId: params.sourceId,
          maturesAt: params.maturesAt,
        },
      });
      return { granted: true };
    } catch (e) {
      // P2002 = unique violation on (sourceType, sourceId, userId): already granted.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        this.logger.log(`Credit for ${params.sourceType}:${params.sourceId} already granted to ${params.userId}.`);
        return { granted: false };
      }
      throw e;
    }
  }

  /**
   * Writes a reversing (negative) entry — e.g. a rewarded referral was refunded.
   * Separate from grant() on purpose: grant() takes an absolute value, so a
   * negative argument there would silently ADD credit instead of removing it.
   *
   * Idempotent on (sourceType, sourceId, userId), so a replayed refund webhook
   * cannot double-reverse. This may drive the balance negative, which is correct:
   * the user spent credit they were not entitled to.
   */
  async reverse(params: {
    userId: string;
    amountMinor: number;
    currency: string;
    description?: string;
    sourceType?: string;
    sourceId?: string;
  }): Promise<{ reversed: boolean }> {
    const amountMinor = -Math.abs(params.amountMinor);
    if (amountMinor === 0) return { reversed: false };

    try {
      await this.prisma.accountCredit.create({
        data: {
          userId: params.userId,
          amountMinor,
          currency: params.currency.toUpperCase(),
          reason: CreditReason.REFUND,
          description: params.description,
          sourceType: params.sourceType,
          sourceId: params.sourceId,
        },
      });
      return { reversed: true };
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        this.logger.log(`Reversal for ${params.sourceType}:${params.sourceId} already recorded.`);
        return { reversed: false };
      }
      throw e;
    }
  }

  /**
   * Consumes up to `requestedMinor` of the user's credit, atomically. Returns how
   * much was actually applied — never more than the balance, never negative.
   *
   * Runs the read and the write in one transaction so two concurrent checkouts
   * cannot both spend the same credit.
   */
  async consume(params: {
    userId: string;
    requestedMinor: number;
    currency: string;
    description?: string;
    sourceType?: string;
    sourceId?: string;
  }): Promise<number> {
    const currency = params.currency.toUpperCase();
    const requested = Math.abs(params.requestedMinor);
    if (requested === 0) return 0;

    const now = new Date();
    // The balance read and the debit insert must be ATOMIC: under the default
    // READ COMMITTED isolation two concurrent checkouts each aggregate the same
    // balance and both insert a full debit — spending the same credit twice.
    // Serializable makes them conflict; the loser aborts instead of overdrawing.
    // (Same read-sum-write race we closed on the bequest cap and upload quota.)
    return this.prisma.$transaction(
      async (tx) => {
        // Only MATURED credit may be spent; held referral commission is excluded.
        const agg = await tx.accountCredit.aggregate({
          where: CreditsService.spendableWhere(params.userId, currency, now),
          _sum: { amountMinor: true },
        });
        const available = agg._sum.amountMinor ?? 0;
        const applied = Math.min(available, requested);
        if (applied <= 0) return 0;

        await tx.accountCredit.create({
          data: {
            userId: params.userId,
            amountMinor: -applied, // negative = consumed
            currency,
            reason: CreditReason.PURCHASE_APPLIED,
            description: params.description ?? 'Applied to purchase',
            sourceType: params.sourceType,
            sourceId: params.sourceId,
          },
        });
        return applied;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  }

  /** Full ledger for a user — powers the "your credit" panel and audit. */
  async history(userId: string) {
    return this.prisma.accountCredit.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }
}
