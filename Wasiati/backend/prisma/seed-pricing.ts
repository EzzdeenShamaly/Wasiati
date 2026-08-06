import { PrismaClient, PriceInterval, Region, SubscriptionTier, PromotionType } from '@prisma/client';
import { isPurchasable } from '../src/commerce/plan-rules';

const prisma = new PrismaClient();

// v2.2 catalog (spec §2, DECISIONS §13 — supersedes DECISIONS §10):
// per-tier MONTHLY or ONE-TIME (plus YEARLY = 10x monthly, two months free).
//   Standard  SAR 19/mo · SAR 349 once   (USD 9/mo · 99 once — prototype plans object)
//   Premium   SAR 39/mo · SAR 649 once   (USD 19/mo · 199 once)
//   Ultimate  US/CA only: USD 39/mo · 399 once (prototype `mu`/`ou`); CAD derived
//             from the prototype's fromUSD table (CAD 1.36, whole-unit rounding).
// There is NO Basic plan in the v2.2 catalog: Basic rows are DEACTIVATED below
// (the BASIC enum + entitlement rank stay so historical purchases keep resolving).
// Amounts are in MINOR units (cents / halalas / dirhams). Admins can still edit
// everything at runtime.
type Seed = {
  tier: SubscriptionTier;
  region: Region;
  currency: string;
  unitAmount: number;
  interval: PriceInterval;
  displayName: string;
  features: string[];
  badge?: string;
  sortOrder: number;
};

// Feature bullets follow spec §2's capability table. LEGAL (DECISIONS §6): burial
// copy says "contributions", NEVER "installments" — consumer-credit law.
const STANDARD_FEATURES = [
  'Legally-valid sharia will + signing instructions',
  "Fara'id computed (Jumhur or your madhhab)",
  'Funeral wishes · witnesses + trustee',
  'Inventory + Excel export · zakat estimate',
  'Inactivity check-in · PDF export',
  'Encrypted vault (5 items)',
];
// NOTE: spec §2 also lists "multiple wills · linked accounts" as a Premium capability.
// It is deliberately NOT sold (owner, 24 Jul 2026). Will limits are tier-INDEPENDENT in
// the product — three unsealed drafts and exactly ONE sealed will, for every tier — and
// there is no linked-account or family-seat concept anywhere in the codebase. A Premium
// buyer receives no more wills than a Standard one, so the bullet is off the card until
// the feature exists. Restore it in the same commit that builds it.
const PREMIUM_FEATURES = [
  'Everything in Standard',
  'Ameen AI (chat + voice)',
  'Video legacy messages',
  'Financial POA · healthcare directive',
  'Unlimited vault',
];
const ULTIMATE_FEATURES = [
  'Everything in Premium',
  "Burial pre-planning at today's price",
  'Zero-interest contributions (3/5/10 yrs)',
  'Provider quotes · family care manager',
];

const YEAR_NOTE = 'Two months free';
const ONCE_NOTE = 'One-time purchase — yours for life';

/** monthly minor units -> yearly (10x = two months free, spec §2). */
const yearly = (monthlyMinor: number) => monthlyMinor * 10;

/**
 * @param onceMinor the one-time price, or NULL for a tier that has no one-time
 *   version. Ultimate passes null: its burial contributions run for 3/5/10 years,
 *   so "Ultimate, paid once" is not a thing that can exist. The real enforcement is
 *   backend/src/commerce/plan-rules.ts — the catalog marks such a row unpurchasable
 *   and checkout refuses it even if an admin hand-creates one — and the assert below
 *   keeps this seed honest against that rule rather than restating it.
 */
function tierRows(
  tier: SubscriptionTier,
  region: Region,
  currency: string,
  monthMinor: number,
  onceMinor: number | null,
  displayName: string,
  features: string[],
  sortOrder: number,
  badge?: string,
): Seed[] {
  if (onceMinor !== null && !isPurchasable(tier, 'ONE_TIME')) {
    throw new Error(`Seed gives ${tier} a one-time price, but plan-rules says ${tier} cannot be sold one-time.`);
  }
  const rows: Seed[] = [
    { tier, region, currency, unitAmount: monthMinor, interval: 'MONTH', displayName, features, badge, sortOrder },
    { tier, region, currency, unitAmount: yearly(monthMinor), interval: 'YEAR', displayName, features: [...features, YEAR_NOTE], badge, sortOrder },
  ];
  if (onceMinor !== null) {
    // One-time first, matching the UI's cycle order (spec §2).
    rows.unshift({ tier, region, currency, unitAmount: onceMinor, interval: 'ONE_TIME', displayName, features: [...features, ONCE_NOTE], badge, sortOrder });
  }
  return rows;
}

const plans: Seed[] = [
  // --- KSA (SAR, halalas) — spec §2's headline prices. No Ultimate: burial is
  // state-provided (free-burial region), so there is nothing to pre-plan.
  ...tierRows('STANDARD', 'KSA', 'SAR', 1900, 34900, 'Standard', STANDARD_FEATURES, 1),
  ...tierRows('PREMIUM', 'KSA', 'SAR', 3900, 64900, 'Premium', PREMIUM_FEATURES, 2, 'Most popular'),

  // --- US (USD, cents) — the prototype plans object's `mu`/`ou` values.
  ...tierRows('STANDARD', 'US', 'USD', 900, 9900, 'Standard', STANDARD_FEATURES, 1),
  ...tierRows('PREMIUM', 'US', 'USD', 1900, 19900, 'Premium', PREMIUM_FEATURES, 2, 'Most popular'),
  // Ultimate: subscription only (see tierRows) — the prototype's `ou` 399 is not seeded.
  ...tierRows('ULTIMATE', 'US', 'USD', 3900, null, 'Ultimate', ULTIMATE_FEATURES, 3),

  // --- Canada (CAD, cents) — derived from USD via the prototype's fromUSD table
  // (CAD 1.36, rounded to whole dollars): 9->12, 99->135, 19->26, 199->271, 39->53.
  ...tierRows('STANDARD', 'CA', 'CAD', 1200, 13500, 'Standard', STANDARD_FEATURES, 1),
  ...tierRows('PREMIUM', 'CA', 'CAD', 2600, 27100, 'Premium', PREMIUM_FEATURES, 2, 'Most popular'),
  ...tierRows('ULTIMATE', 'CA', 'CAD', 5300, null, 'Ultimate', ULTIMATE_FEATURES, 3),
];

async function main() {
  for (const p of plans) {
    await prisma.pricingPlan.upsert({
      where: { tier_region_interval: { tier: p.tier, region: p.region, interval: p.interval } },
      // v2.2 is a deliberate catalog REPLACEMENT ("implement to the dot"), so this
      // seed updates prices too — running it is an explicit adoption of the v2.2
      // price list, not an accidental clobber (seeds only run when invoked; admin
      // edits made AFTER seeding are untouched until the next deliberate re-seed).
      update: {
        currency: p.currency,
        unitAmount: p.unitAmount,
        displayName: p.displayName,
        features: p.features,
        badge: p.badge ?? null,
        sortOrder: p.sortOrder,
        active: true,
      },
      create: { ...p },
    });
  }

  // v2.2 removes Basic from the catalog. Deactivate (never delete) so historical
  // subscriptions/purchases keep resolving and an admin can reactivate if needed.
  const basicOff = await prisma.pricingPlan.updateMany({
    where: { tier: 'BASIC' },
    data: { active: false },
  });

  // Ultimate is subscription-only. Earlier seeds DID create an Ultimate one-time row
  // (USD 399 / CAD 543); deactivate any that a previous run left behind, or a database
  // seeded before this change would keep showing a price nobody is allowed to buy.
  const ultimateOnceOff = await prisma.pricingPlan.updateMany({
    where: { tier: 'ULTIMATE', interval: 'ONE_TIME' },
    data: { active: false },
  });

  // A sample launch promotion + offer so the storefront has something to show.
  const promo = await prisma.promotion.upsert({
    where: { code: 'LAUNCH25' },
    update: {},
    create: {
      code: 'LAUNCH25',
      type: PromotionType.PERCENT,
      value: 25,
      description: '25% off your first subscription',
      appliesToTiers: ['STANDARD', 'PREMIUM', 'ULTIMATE'],
      appliesToRegions: [],
      firstTimeOnly: true,
      active: true,
    },
  });

  // WASIATI30 — the brand-name 30% code. `update: {}` on the upsert deliberately
  // leaves an existing row alone: re-running the seed must never silently reset a
  // redemption count or revive a code an admin has paused.
  await prisma.promotion.upsert({
    where: { code: 'WASIATI30' },
    update: {},
    create: {
      code: 'WASIATI30',
      type: PromotionType.PERCENT,
      value: 30,
      description: '30% off your subscription',
      // All tiers, all regions — it is the general-purpose brand code.
      appliesToTiers: [],
      appliesToRegions: [],
      // Caps: 30% is the deepest discount we run, so it is bounded on both axes —
      // one per customer (first purchase only) and a hard ceiling on total uses, so
      // a leaked code cannot discount the whole book indefinitely.
      firstTimeOnly: true,
      maxRedemptions: 1000,
      endsAt: new Date('2027-01-01T00:00:00Z'),
      active: true,
    },
  });

  // The offer must LINK to the promotion, otherwise its CTA has no code to apply.
  const existingOffer = await prisma.offer.findFirst({ where: { title: 'Launch offer' } });
  if (!existingOffer) {
    await prisma.offer.create({
      data: {
        title: 'Launch offer',
        subtitle: 'Save 25% on your first subscription',
        badge: 'Limited time',
        ctaLabel: 'Apply LAUNCH25',
        promotionId: promo.id,
        sortOrder: 0,
        active: true,
      },
    });
  } else if (!existingOffer.promotionId) {
    await prisma.offer.update({
      where: { id: existingOffer.id },
      data: { promotionId: promo.id, ctaLabel: 'Apply LAUNCH25' },
    });
  }

  const active = await prisma.pricingPlan.count({ where: { active: true } });
  const annual = await prisma.pricingPlan.count({ where: { interval: 'YEAR', active: true } });
  const oneTime = await prisma.pricingPlan.count({ where: { interval: 'ONE_TIME', active: true } });
  const promos = await prisma.promotion.findMany({ where: { active: true }, select: { code: true } });
  console.log(
    `v2.2 pricing catalog seeded: ${active} active plans (${oneTime} one-time, ${annual} annual), ` +
      `${basicOff.count} Basic rows deactivated, ${ultimateOnceOff.count} Ultimate one-time rows deactivated, ` +
      `promo LAUNCH25 linked to 1 offer. Active codes: ${promos.map((p) => p.code).join(', ')}.`,
  );
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
