-- Zakat: asset categories, the Hijri ḥawl anniversary, and admin-published settings.

-- CRYPTO is its own type precisely so it can be EXCLUDED from the zakat base
-- rather than silently swept into OTHER.
ALTER TYPE "AssetType" ADD VALUE IF NOT EXISTS 'CASH';
ALTER TYPE "AssetType" ADD VALUE IF NOT EXISTS 'SHARES';
ALTER TYPE "AssetType" ADD VALUE IF NOT EXISTS 'GOLD';
ALTER TYPE "AssetType" ADD VALUE IF NOT EXISTS 'CRYPTO';

-- Ḥawl anniversary: Hijri day (1..30) and month (1..12). Never a Gregorian date.
ALTER TABLE "User" ADD COLUMN "hawlDay" INTEGER;
ALTER TABLE "User" ADD COLUMN "hawlMonth" INTEGER;

-- Admin-editable, publish-live settings (the Content tab).
CREATE TABLE "AppSetting" (
  "key"       TEXT NOT NULL,
  "value"     TEXT NOT NULL,
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AppSetting_pkey" PRIMARY KEY ("key")
);
