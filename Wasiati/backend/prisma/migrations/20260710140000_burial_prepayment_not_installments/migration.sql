-- Burial is PREPAID ESCROW, not installments (see docs/DECISIONS.md §6).
-- Contributions are the customer's own money, held in trust and refundable; they
-- never lock the subscription. RENAME rather than drop/recreate, so existing rows
-- and their foreign keys survive.

ALTER TABLE "GraveInstallmentPlan" RENAME TO "BurialPrepaymentPlan";

-- Keep index/constraint names in step with the table, or Prisma sees drift.
ALTER INDEX "GraveInstallmentPlan_pkey" RENAME TO "BurialPrepaymentPlan_pkey";
ALTER INDEX "GraveInstallmentPlan_userId_idx" RENAME TO "BurialPrepaymentPlan_userId_idx";
ALTER TABLE "BurialPrepaymentPlan"
  RENAME CONSTRAINT "GraveInstallmentPlan_userId_fkey" TO "BurialPrepaymentPlan_userId_fkey";

ALTER TYPE "GraveInstallmentStatus" RENAME TO "BurialPlanStatus";
-- "MATURED" was debt language: the plan is simply fully funded.
ALTER TYPE "BurialPlanStatus" RENAME VALUE 'MATURED' TO 'FULLY_FUNDED';

-- Cancelling a plan returns the contributions; record what is owed back.
ALTER TABLE "BurialPrepaymentPlan" ADD COLUMN "refundDueMinor" INTEGER;
ALTER TABLE "BurialPrepaymentPlan" ADD COLUMN "cancelledAt" TIMESTAMP(3);
