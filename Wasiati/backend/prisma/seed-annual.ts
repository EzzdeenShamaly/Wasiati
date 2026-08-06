/**
 * Adds an annual (YEAR) plan for every active monthly plan, priced at 10x the
 * CURRENT monthly amount — i.e. two months free. Derives from the live database
 * rather than hard-coded defaults, so admin price edits are respected.
 *
 * Idempotent: skips any (tier, region, YEAR) plan that already exists.
 * Run: npx ts-node prisma/seed-annual.ts
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const ANNUAL_MULTIPLIER = 10; // 12 months billed as 10 → two months free

async function main() {
  const monthly = await prisma.pricingPlan.findMany({ where: { interval: 'MONTH', active: true } });
  if (monthly.length === 0) {
    console.log('No active monthly plans found — run seed-pricing first.');
    return;
  }

  let created = 0;
  let skipped = 0;
  for (const m of monthly) {
    const existing = await prisma.pricingPlan.findUnique({
      where: { tier_region_interval: { tier: m.tier, region: m.region, interval: 'YEAR' } },
    });
    if (existing) {
      skipped++;
      continue;
    }
    // `features` is a Json column — normalise before appending.
    const baseFeatures = Array.isArray(m.features) ? (m.features as string[]) : [];
    await prisma.pricingPlan.create({
      data: {
        tier: m.tier,
        region: m.region,
        currency: m.currency,
        unitAmount: m.unitAmount * ANNUAL_MULTIPLIER,
        interval: 'YEAR',
        displayName: m.displayName,
        features: [...baseFeatures, 'Two months free'],
        badge: m.badge,
        sortOrder: m.sortOrder,
        active: true,
      },
    });
    created++;
  }

  const annual = await prisma.pricingPlan.count({ where: { interval: 'YEAR' } });
  console.log(`Annual plans: ${created} created, ${skipped} already existed. Total annual now: ${annual}.`);
  // No provider sync step: unitAmount here is what gets charged at checkout.
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
