import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appBaseUrl as resolveAppBaseUrl } from '../common/app-url';
import { CreditReason, PriceInterval, Prisma, Region, ReferralStatus, SubscriptionTier } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { CreditsService } from '../credits/credits.service';
import { resolveBillingCurrency } from '../common/geo.util';

/**
 * Referral programme (v2).
 *
 * THE FRIEND gets 10% off at checkout — a discount, not credit, so there is nothing
 * to claw back. It is offered only on plans that already carry a one-year commitment
 * (annual or one-time), which makes "no cancellation before a year" structural
 * rather than a clawback we would have to chase.
 *
 * THE REFERRER earns 2.5% of the friend's FIRST-YEAR VALUE (the annual price, or the
 * one-time price actually paid), granted as ACCOUNT CREDIT rather than cash — no
 * payout rails, no KYC, no tax reporting. The credit is visible immediately but HELD
 * for REFERRAL_HOLD_DAYS (100) before it can be spent, covering the refund and
 * chargeback window on the friend's purchase.
 *
 * Currency: referrer and friend are ALWAYS in the same region, because each region is
 * a physically separate database (data residency) — a cross-region Referral row
 * cannot exist. So the commission never needs an FX conversion.
 *
 * Qualifying purchase by the REFERRED user (either one):
 *   · an ANNUAL subscription (interval = YEAR — a minimum 1-year commitment)
 *   · the ONE-TIME plan (interval = ONE_TIME)
 * A monthly subscription does NOT qualify.
 *
 * TWO caps, whichever binds first:
 *   · per referrer: $500-equivalent of commission per calendar year. A referral that
 *     would breach it is paid only up to the ceiling; once the ceiling is reached,
 *     further referrals earn nothing and are marked CAPPED.
 *   · programme-wide: REFERRAL_YEARLY_CAP (default 100) payouts per calendar year.
 * Capped referrals are still recorded — never silently dropped.
 */

/** A credit applied to one user's account-credit balance. */
export interface ReferralGrant {
  userId: string;
  amountMinor: number;
  currency: string;
  maturesAt: Date;
}

export interface ReferralOutcome {
  outcome: 'skipped' | 'not-qualifying' | 'rewarded' | 'capped';
  grants: ReferralGrant[];
}

/** Commission rate, in basis points. 250 bp = 2.5%. */
const REFERRAL_RATE_BP = 250;

/** Days the referrer's commission is held before it becomes spendable. */
export const REFERRAL_HOLD_DAYS = 100;

/** The friend's checkout discount. */
export const REFERRED_DISCOUNT_PERCENT = 10;

/**
 * $500-equivalent per referrer, per calendar year, in MINOR units of the region's
 * own currency. A Record (not a switch with `default`) so adding a region fails to
 * COMPILE rather than silently applying the wrong ceiling.
 */
const REFERRER_YEARLY_CAP: Record<Region, { capMinor: number; currency: string }> = {
  US: { capMinor: 50_000, currency: 'USD' }, // $500.00
  CA: { capMinor: 70_000, currency: 'CAD' }, // CA$700 ≈ $500 USD
  KSA: { capMinor: 187_500, currency: 'SAR' }, // SAR 1,875 ≈ $500 USD
};
/** Used when the region's currency is not enabled and we bill in USD instead. */
const FALLBACK_CAP = { capMinor: 50_000, currency: 'USD' };

@Injectable()
export class ReferralsService {
  private readonly logger = new Logger(ReferralsService.name);

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    private credits: CreditsService,
  ) {}

  private get yearlyCap(): number {
    return Number(this.config.get('REFERRAL_YEARLY_CAP') ?? 100);
  }

  /**
   * The ceiling on one referrer's commission for a calendar year, in the currency
   * they are actually billed in — credit must be spendable, so it has to match.
   */
  private capFor(region: Region): { capMinor: number; currency: string } {
    const billing = resolveBillingCurrency(region);
    const cap = REFERRER_YEARLY_CAP[region];
    return billing === cap.currency ? cap : FALLBACK_CAP;
  }

  /** 2.5% of the friend's first-year value, rounded DOWN to the minor unit. */
  static commissionMinor(basisMinor: number): number {
    return Math.floor((Math.max(0, basisMinor) * REFERRAL_RATE_BP) / 10_000);
  }

  /** A qualifying purchase is an annual subscription or the one-time plan. */
  static isQualifying(interval: PriceInterval): boolean {
    return interval === 'YEAR' || interval === 'ONE_TIME';
  }

  private newCode(): string {
    // 8 chars, unambiguous alphabet (no 0/O/1/I).
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const bytes = randomBytes(8);
    return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
  }

  /** Idempotently returns this user's shareable code, creating it on first call. */
  async getOrCreateCode(userId: string): Promise<string> {
    const existing = await this.prisma.referralCode.findUnique({ where: { userId } });
    if (existing) return existing.code;

    // Retry on the (astronomically unlikely) code collision.
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = this.newCode();
      try {
        const created = await this.prisma.referralCode.create({ data: { userId, code } });
        return created.code;
      } catch {
        // unique violation → try another code
      }
    }
    throw new BadRequestException('Could not allocate a referral code. Please try again.');
  }

  /**
   * The discount the CURRENT user is entitled to at checkout, as a percentage.
   * Only for a friend who was referred, on a plan carrying a one-year commitment.
   */
  async pendingDiscountPercent(userId: string, interval: PriceInterval): Promise<number> {
    if (!ReferralsService.isQualifying(interval)) return 0;
    const referral = await this.prisma.referral.findUnique({ where: { referredUserId: userId } });
    if (!referral || referral.status !== ReferralStatus.PENDING) return 0;
    return REFERRED_DISCOUNT_PERCENT;
  }

  /** My code, share link and running totals. */
  async summary(userId: string, appBaseUrl?: string) {
    const code = await this.getOrCreateCode(userId);
    const [made, user] = await Promise.all([
      this.prisma.referral.findMany({ where: { referrerId: userId } }),
      this.prisma.user.findUnique({ where: { id: userId } }),
    ]);
    const rewarded = made.filter((r) => r.status === 'REWARDED');
    const base = appBaseUrl ?? resolveAppBaseUrl(this.config);

    const cap = user ? this.capFor(user.region) : FALLBACK_CAP;
    const year = new Date().getUTCFullYear();
    const earnedThisYear = rewarded
      .filter((r) => r.rewardYear === year)
      .reduce((s, r) => s + (r.referrerRewardMinor ?? 0), 0);

    const balances = await this.credits.balances(userId, cap.currency);

    return {
      code,
      shareUrl: `${base}/register?ref=${code}`,
      invited: made.length,
      qualified: made.filter((r) => r.status === 'QUALIFIED').length,
      rewarded: rewarded.length,
      capped: made.filter((r) => r.status === 'CAPPED').length,
      currency: cap.currency,
      // What they have earned, what they may spend today, and what is still held.
      earnedThisYearMinor: earnedThisYear,
      yearlyCapMinor: cap.capMinor,
      remainingThisYearMinor: Math.max(0, cap.capMinor - earnedThisYear),
      creditSpendableMinor: balances.spendableMinor,
      creditHeldMinor: balances.pendingMinor,
      holdDays: REFERRAL_HOLD_DAYS,
      friendDiscountPercent: REFERRED_DISCOUNT_PERCENT,
    };
  }

  /**
   * Attach the current user to a referrer's code. Must happen BEFORE the user's
   * qualifying purchase. Rejects self-referral and re-referral.
   */
  async claim(referredUserId: string, rawCode: string) {
    const code = rawCode.trim().toUpperCase();
    const owner = await this.prisma.referralCode.findUnique({ where: { code } });
    if (!owner) throw new NotFoundException('That referral code does not exist.');
    if (owner.userId === referredUserId) {
      throw new BadRequestException('You cannot refer yourself.');
    }

    const already = await this.prisma.referral.findUnique({ where: { referredUserId } });
    if (already) throw new BadRequestException('This account has already used a referral code.');

    // A user who has already bought cannot retroactively be referred.
    const priorPurchase = await this.prisma.subscription.findFirst({ where: { userId: referredUserId } });
    if (priorPurchase) {
      throw new BadRequestException('Referral codes must be applied before your first purchase.');
    }

    return this.prisma.referral.create({
      data: {
        referrerId: owner.userId,
        referredUserId,
        code,
        status: ReferralStatus.PENDING,
        referredDiscountPercent: REFERRED_DISCOUNT_PERCENT,
      },
    });
  }

  /**
   * Called from the payment webhook when the referred user completes a qualifying
   * checkout. `basisMinor` is the first-year value they actually paid, in the
   * currency they were charged. Idempotent: a referral past PENDING is skipped.
   */
  async handleQualifyingPurchase(params: {
    userId: string;
    interval: PriceInterval;
    tier: SubscriptionTier;
    basisMinor: number;
    currency: string;
  }): Promise<ReferralOutcome> {
    const referral = await this.prisma.referral.findUnique({ where: { referredUserId: params.userId } });
    if (!referral || referral.status !== ReferralStatus.PENDING) return { outcome: 'skipped', grants: [] };

    if (!ReferralsService.isQualifying(params.interval)) return { outcome: 'not-qualifying', grants: [] };

    const referrer = await this.prisma.user.findUnique({ where: { id: referral.referrerId } });
    if (!referrer) return { outcome: 'skipped', grants: [] };

    const now = new Date();
    const year = now.getUTCFullYear();
    const qualifyingEvent = params.interval === 'YEAR' ? 'ANNUAL_SUBSCRIPTION' : 'ONE_TIME';
    const maturesAt = new Date(now.getTime() + REFERRAL_HOLD_DAYS * 24 * 60 * 60 * 1000);

    const cap = this.capFor(referrer.region);
    const commission = ReferralsService.commissionMinor(params.basisMinor);

    // Enforce BOTH caps atomically, then either reward or mark CAPPED. The cap
    // reads aggregate OTHER Referral rows, so this must run Serializable: under
    // READ COMMITTED two near-simultaneous qualifying purchases each read the
    // pre-increment totals and both pay, overshooting the yearly ceilings.
    const result = await this.prisma.$transaction(
      async (tx) => {
      const rewardedThisYear = await tx.referral.count({
        where: { status: ReferralStatus.REWARDED, rewardYear: year },
      });

      const earned = await tx.referral.aggregate({
        where: { referrerId: referrer.id, status: ReferralStatus.REWARDED, rewardYear: year },
        _sum: { referrerRewardMinor: true },
      });
      const earnedThisYear = earned._sum.referrerRewardMinor ?? 0;
      const remaining = Math.max(0, cap.capMinor - earnedThisYear);

      // Pay up to the ceiling; once it is reached, further referrals earn nothing.
      const payable = Math.min(commission, remaining);
      const programmeCapped = rewardedThisYear >= this.yearlyCap;

      if (programmeCapped || payable <= 0) {
        await tx.referral.update({
          where: { id: referral.id },
          data: {
            status: ReferralStatus.CAPPED,
            qualifyingEvent,
            qualifiedAt: now,
            rewardYear: year,
            referrerRewardBasisMinor: params.basisMinor,
          },
        });
        return { outcome: 'capped' as const, payable: 0, reason: programmeCapped ? 'programme' : 'referrer' };
      }

      await tx.referral.update({
        where: { id: referral.id },
        data: {
          status: ReferralStatus.REWARDED,
          qualifyingEvent,
          qualifiedAt: now,
          rewardedAt: now,
          rewardYear: year,
          referrerRewardBasisMinor: params.basisMinor,
          referrerRewardMinor: payable,
          referrerRewardCurrency: cap.currency,
          referrerRewardMaturesAt: maturesAt,
        },
      });
      return { outcome: 'rewarded' as const, payable, reason: '' };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );

    if (result.outcome === 'capped') {
      this.logger.warn(
        `Referral ${referral.id} qualified but the ${year} ${result.reason} cap is reached — marked CAPPED, not paid.`,
      );
      return { outcome: 'capped', grants: [] };
    }

    if (result.payable < commission) {
      this.logger.warn(
        `Referral ${referral.id}: commission trimmed from ${commission} to ${result.payable} ${cap.currency} by the per-referrer yearly ceiling.`,
      );
    }

    const grant: ReferralGrant = {
      userId: referrer.id,
      amountMinor: result.payable,
      currency: cap.currency,
      maturesAt,
    };

    // Idempotent on (Referral, referral.id, user), so a replayed webhook cannot
    // double-credit. Held until maturesAt.
    await this.credits.grant({
      userId: grant.userId,
      amountMinor: grant.amountMinor,
      currency: grant.currency,
      reason: CreditReason.REFERRAL_REWARD,
      description: `Referral commission (${REFERRAL_RATE_BP / 100}% of first-year value)`,
      sourceType: 'Referral',
      sourceId: referral.id,
      maturesAt,
    });

    this.logger.log(
      `Referral ${referral.id} rewarded (${qualifyingEvent}); ${result.payable} ${cap.currency} credited, spendable ${maturesAt.toISOString()}.`,
    );
    return { outcome: 'rewarded', grants: [grant] };
  }

  /** Reverses the commission when the qualifying purchase is refunded or charged back. */
  async rejectForRefund(referredUserId: string, reason = 'Qualifying purchase refunded') {
    const referral = await this.prisma.referral.findUnique({ where: { referredUserId } });
    if (!referral || referral.status === ReferralStatus.REJECTED) return;

    const wasRewarded = referral.status === ReferralStatus.REWARDED;
    await this.prisma.referral.update({
      where: { id: referral.id },
      data: { status: ReferralStatus.REJECTED, rejectedReason: reason },
    });

    // The ledger is append-only, so we write a reversing (negative) entry rather
    // than deleting the grant. A distinct sourceType keeps it from colliding with
    // the original grant's idempotency key. The friend had a discount, not credit,
    // so there is nothing to reverse on their side.
    if (wasRewarded && referral.referrerRewardMinor && referral.referrerRewardCurrency) {
      await this.credits.reverse({
        userId: referral.referrerId,
        amountMinor: referral.referrerRewardMinor,
        currency: referral.referrerRewardCurrency,
        description: `Referral commission reversed: ${reason}`,
        sourceType: 'ReferralReversal',
        sourceId: referral.id,
      });
    }

    this.logger.warn(`Referral ${referral.id} rejected: ${reason}`);
  }
}
