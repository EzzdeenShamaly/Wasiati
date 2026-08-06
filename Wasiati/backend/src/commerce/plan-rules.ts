import { BadRequestException } from '@nestjs/common';
import { PriceInterval, SubscriptionTier } from '@prisma/client';

/**
 * Which (tier, interval) combinations may actually be SOLD.
 *
 * This is a product rule, not catalog data, so it lives in code: the catalog is
 * admin-editable at runtime, and an admin adding a row must not be able to put a
 * plan on sale that we have decided cannot exist. The catalog marks rows with
 * `purchasable` from here (the app hides them) and checkout asserts it again —
 * the UI is a courtesy, the server check is the rule.
 */

/**
 * ULTIMATE is a SUBSCRIPTION tier only — it cannot be bought one-time.
 *
 * Ultimate's reason to exist is burial pre-planning: a grave reserved at today's
 * price, paid for by zero-interest CONTRIBUTIONS over 3/5/10 years (spec §2).
 * Those contributions are inherently recurring — an obligation that continues for
 * years — so a single up-front payment cannot buy the tier. Selling "Ultimate,
 * once" would promise a burial benefit funded by a stream of payments the buyer
 * never agreed to make, and every contribution afterwards would have no
 * subscription to hang from.
 *
 * (Standard and Premium are pure software entitlements, so paying once for life
 * is coherent there — see the seed's one-time rows.)
 */
export function isPurchasable(tier: SubscriptionTier, interval: PriceInterval): boolean {
  return !(tier === SubscriptionTier.ULTIMATE && interval === PriceInterval.ONE_TIME);
}

/** Server-side gate for checkout. The client hides it; this is what enforces it. */
export function assertPurchasable(tier: SubscriptionTier, interval: PriceInterval): void {
  if (isPurchasable(tier, interval)) return;
  throw new BadRequestException(
    'Ultimate is a subscription — its burial contributions are recurring, so it cannot be bought as a one-time purchase. Choose monthly or yearly.',
  );
}
