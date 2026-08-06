import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Owner-only business insights. Returns structured KPIs plus a natural-language
 * `headline` sentence — the headline is what a Siri Shortcut / voice channel reads
 * aloud ("how is my business doing"). Access is restricted to ADMIN (the owner) at
 * the controller; nothing here exposes any individual customer's personal data.
 */
@Injectable()
export class MetricsService {
  constructor(private prisma: PrismaService) {}

  private since(days: number) {
    return new Date(Date.now() - days * 86_400_000);
  }

  async summary() {
    const [
      totalUsers,
      new7d,
      new30d,
      kycVerified,
      activeSubs,
      pastDue,
      totalWills,
      sealedWills,
      pendingClaims,
      usdMonthlyPlans,
      activeForMrr,
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.user.count({ where: { createdAt: { gte: this.since(7) } } }),
      this.prisma.user.count({ where: { createdAt: { gte: this.since(30) } } }),
      this.prisma.user.count({ where: { idVerificationStatus: 'VERIFIED' } }),
      this.prisma.subscription.count({ where: { status: 'ACTIVE' } }),
      this.prisma.subscription.count({ where: { status: 'PAST_DUE' } }),
      this.prisma.will.count(),
      this.prisma.will.count({ where: { status: 'SEALED' } }),
      this.prisma.deathClaim.count({ where: { status: { in: ['SUBMITTED', 'UNDER_REVIEW'] } } }),
      this.prisma.pricingPlan.findMany({ where: { currency: 'USD', active: true, interval: 'MONTH' } }),
      this.prisma.subscription.findMany({ where: { status: 'ACTIVE' }, select: { tier: true } }),
    ]);

    // Active subscriptions grouped by tier.
    const byTier: Record<string, number> = { BASIC: 0, STANDARD: 0, PREMIUM: 0, ULTIMATE: 0 };
    for (const s of activeForMrr) byTier[s.tier] = (byTier[s.tier] ?? 0) + 1;

    // Approx MRR in USD: sum each active sub's monthly USD plan price (best-effort).
    const priceByTier = new Map<string, number>();
    for (const p of usdMonthlyPlans) if (!priceByTier.has(p.tier)) priceByTier.set(p.tier, p.unitAmount);
    const approxMrrMinor = activeForMrr.reduce((sum, s) => sum + (priceByTier.get(s.tier) ?? 0), 0);
    const approxMrr = approxMrrMinor / 100;

    const headline =
      `You have ${activeSubs} active subscription${activeSubs === 1 ? '' : 's'}` +
      `${approxMrr > 0 ? ` and about $${approxMrr.toLocaleString('en-US', { maximumFractionDigits: 0 })} in monthly recurring revenue` : ''}. ` +
      `${new7d} new sign-up${new7d === 1 ? '' : 's'} this week` +
      `${pastDue > 0 ? `, ${pastDue} payment${pastDue === 1 ? '' : 's'} past due` : ''}` +
      `${pendingClaims > 0 ? `, and ${pendingClaims} death claim${pendingClaims === 1 ? '' : 's'} awaiting review` : ''}.`;

    return {
      generatedAt: new Date().toISOString(),
      headline,
      users: { total: totalUsers, new7d, new30d, kycVerified },
      subscriptions: { active: activeSubs, pastDue, byTier },
      revenue: { approxMrr, currency: 'USD', note: 'Best-effort estimate from the USD monthly catalog.' },
      wills: { total: totalWills, sealed: sealedWills },
      operations: { pendingDeathClaims: pendingClaims },
    };
  }
}
