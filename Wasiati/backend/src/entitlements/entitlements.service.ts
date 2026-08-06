import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SubscriptionTier } from '@prisma/client';

export type Feature =
  | 'immutableWill'
  | 'unlimitedEdits'
  | 'vault'
  | 'videoMessages'
  | 'aiIntake'
  | 'directives'
  | 'burialPlanning';

export type EntitlementSource = 'admin' | 'comp' | 'subscription' | 'none';

export interface Entitlement {
  tier: SubscriptionTier | null;
  source: EntitlementSource;
  isAdmin: boolean;
  features: Record<Feature, boolean>;
  expiresAt: Date | null;
}

const TIER_ORDER: SubscriptionTier[] = [
  SubscriptionTier.BASIC,
  SubscriptionTier.STANDARD,
  SubscriptionTier.PREMIUM,
  SubscriptionTier.ULTIMATE,
];

function featuresForTier(tier: SubscriptionTier | null): Record<Feature, boolean> {
  const rank = tier ? TIER_ORDER.indexOf(tier) : -1;
  return {
    immutableWill: rank >= 0, // BASIC+
    unlimitedEdits: rank >= 1, // STANDARD+
    vault: rank >= 1, // STANDARD+
    videoMessages: rank >= 2, // PREMIUM+
    aiIntake: rank >= 2, // PREMIUM+
    directives: rank >= 2, // PREMIUM+ (POA / healthcare directive — spec §2)
    burialPlanning: rank >= 3, // ULTIMATE
  };
}

/**
 * Single source of truth for what a user is entitled to.
 *
 * Resolution order:
 *   1. ADMIN role  -> full access (ULTIMATE, every feature), NO payment required.
 *      This is the "admins can demo/test the whole site without paying" path.
 *   2. Comp grant  -> an admin-granted tier (demo/test accounts), bypasses billing.
 *   3. Subscription-> the user's active paid subscription.
 *   4. none        -> free user, no paid features.
 *
 * The paywall (FeatureGuard) and the Flutter UI both gate against this, so the
 * admin/comp bypass applies everywhere automatically.
 */
@Injectable()
export class EntitlementsService {
  constructor(private prisma: PrismaService) {}

  async resolve(userId: string): Promise<Entitlement> {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { role: true, compTier: true, compExpiresAt: true },
    });
    if (!user) {
      return { tier: null, source: 'none', isAdmin: false, features: featuresForTier(null), expiresAt: null };
    }

    if (user.role === 'ADMIN') {
      return {
        tier: SubscriptionTier.ULTIMATE,
        source: 'admin',
        isAdmin: true,
        features: featuresForTier(SubscriptionTier.ULTIMATE),
        expiresAt: null,
      };
    }

    const compValid = user.compTier && (!user.compExpiresAt || user.compExpiresAt > new Date());
    if (compValid) {
      return {
        tier: user.compTier!,
        source: 'comp',
        isAdmin: false,
        features: featuresForTier(user.compTier!),
        expiresAt: user.compExpiresAt ?? null,
      };
    }

    // Pick the HIGHEST-tier active subscription, not the most recent: a one-time Basic
    // purchase now creates an ACTIVE subscription, so a Standard/Premium subscriber must
    // not be downgraded to Basic just because the one-time row is newer.
    //
    // PAST_DUE counts, deliberately — the same pair the billing cron retries. The dunning
    // design (subscriptions.service.ts) says it in words: "Access is not revoked the
    // instant a card fails — people's cards expire, and this is a will." A card decline
    // moves the row to PAST_DUE and the cron retries daily up to MAX_FAILURES before
    // CANCELING, so PAST_DUE is by definition inside that grace window; matching ACTIVE
    // alone revoked access at the first decline, contradicting the design in the same
    // codebase and yanking the vault/paywall out from under someone whose card simply
    // expired. Access ends where dunning ends: at CANCELED, which this rightly excludes.
    const subs = await this.prisma.subscription.findMany({
      where: { userId, status: { in: ['ACTIVE', 'PAST_DUE'] } },
    });
    if (subs.length) {
      const best = subs.reduce((a, b) => (TIER_ORDER.indexOf(b.tier) > TIER_ORDER.indexOf(a.tier) ? b : a));
      return {
        tier: best.tier,
        source: 'subscription',
        isAdmin: false,
        features: featuresForTier(best.tier),
        expiresAt: best.currentPeriodEnd ?? null,
      };
    }

    return { tier: null, source: 'none', isAdmin: false, features: featuresForTier(null), expiresAt: null };
  }

  async hasFeature(userId: string, feature: Feature): Promise<boolean> {
    const entitlement = await this.resolve(userId);
    return entitlement.features[feature] === true;
  }

  // --- admin-managed comp grants -------------------------------------------

  async grantComp(targetUserId: string, tier: SubscriptionTier, adminId: string, expiresAt?: Date): Promise<Entitlement> {
    await this.prisma.user.update({
      where: { id: targetUserId },
      data: { compTier: tier, compExpiresAt: expiresAt ?? null, compGrantedBy: adminId },
    });
    return this.resolve(targetUserId);
  }

  async revokeComp(targetUserId: string): Promise<Entitlement> {
    await this.prisma.user.update({
      where: { id: targetUserId },
      data: { compTier: null, compExpiresAt: null, compGrantedBy: null },
    });
    return this.resolve(targetUserId);
  }
}
