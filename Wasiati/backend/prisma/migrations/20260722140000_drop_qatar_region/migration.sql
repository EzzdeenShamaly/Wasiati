-- Qatar is no longer a market (owner, 22 Jul 2026). QA leaves the Region enum, the two
-- Qatar-specific asset types go with it, and the seeded QA pricing plans are removed.
--
-- Checked before writing this, rather than assumed: zero User rows in QA, zero Assets of
-- either QA type, zero Offers, zero BurialEstimateRequests, zero Promotions naming QA. The
-- only QA data was 7 PricingPlan rows — the Qatar price list — which is exactly what should
-- disappear when a market does.
--
-- PostgreSQL cannot remove a value from an enum in place, so each type is rebuilt and every
-- dependent column swapped. Region is referenced by five places including one ARRAY column
-- (Promotion.appliesToRegions), which needs the text[] round-trip.

DELETE FROM "PricingPlan" WHERE "region" = 'QA';

-- Region: KSA | CA | US | QA  ->  KSA | CA | US
ALTER TYPE "Region" RENAME TO "Region_old";
CREATE TYPE "Region" AS ENUM ('KSA', 'CA', 'US');

ALTER TABLE "User" ALTER COLUMN "region" TYPE "Region" USING ("region"::text::"Region");
ALTER TABLE "PricingPlan" ALTER COLUMN "region" TYPE "Region" USING ("region"::text::"Region");
ALTER TABLE "Offer" ALTER COLUMN "region" TYPE "Region" USING ("region"::text::"Region");
ALTER TABLE "BurialEstimateRequest" ALTER COLUMN "region" TYPE "Region" USING ("region"::text::"Region");
ALTER TABLE "Promotion" ALTER COLUMN "appliesToRegions" TYPE "Region"[] USING ("appliesToRegions"::text[]::"Region"[]);

DROP TYPE "Region_old";

-- AssetType: drop QA_END_OF_SERVICE_BENEFITS and QA_GRSIA_PENSION.
ALTER TYPE "AssetType" RENAME TO "AssetType_old";
CREATE TYPE "AssetType" AS ENUM (
  'REAL_ESTATE', 'BANK_ACCOUNT', 'VEHICLE', 'BUSINESS_OWNERSHIP', 'PENSION', 'LIABILITY', 'OTHER',
  'CASH', 'SHARES', 'GOLD', 'CRYPTO',
  'CA_RRSP', 'CA_TFSA', 'CA_RESP', 'CA_RRIF',
  'US_401K', 'US_IRA', 'US_ROTH_IRA', 'US_529_PLAN',
  'KSA_END_OF_SERVICE_BENEFITS', 'KSA_GOSI_PENSION'
);
ALTER TABLE "Asset" ALTER COLUMN "type" TYPE "AssetType" USING ("type"::text::"AssetType");
DROP TYPE "AssetType_old";
