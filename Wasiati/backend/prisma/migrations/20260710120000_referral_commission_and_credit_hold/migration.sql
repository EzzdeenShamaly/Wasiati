-- Referral programme v2: 2.5% commission on the friend's first-year value,
-- a 10% discount for the friend, and a 100-day hold before credit is spendable.

-- Credit maturation. NULL = spendable immediately (all existing rows).
ALTER TABLE "AccountCredit" ADD COLUMN "maturesAt" TIMESTAMP(3);
CREATE INDEX "AccountCredit_userId_currency_maturesAt_idx"
  ON "AccountCredit" ("userId", "currency", "maturesAt");

-- Commission basis + hold, and the friend's discount.
ALTER TABLE "Referral" ADD COLUMN "referrerRewardBasisMinor" INTEGER;
ALTER TABLE "Referral" ADD COLUMN "referrerRewardMaturesAt" TIMESTAMP(3);
ALTER TABLE "Referral" ADD COLUMN "referredDiscountPercent" INTEGER;

-- The friend is now rewarded with a checkout discount, not account credit.
-- No production rows exist yet (the programme has never run), so these columns
-- are dropped rather than left to rot as permanently-NULL dead weight.
ALTER TABLE "Referral" DROP COLUMN "referredRewardMinor";
ALTER TABLE "Referral" DROP COLUMN "referredRewardCurrency";
