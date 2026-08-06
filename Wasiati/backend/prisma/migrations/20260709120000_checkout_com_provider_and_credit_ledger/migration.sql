-- Flip the payment stack from Stripe to Checkout.com.
--
-- The dropped stripe* columns hold identifiers that are meaningless outside
-- Stripe (customer/product/price/coupon ids), so there is nothing to migrate —
-- they are dropped rather than renamed.
--
-- Checkout.com has no subscription object, no billing portal and no customer
-- balance, so we take ownership of: the billing cycle (Subscription.interval /
-- currentPeriodEnd / paymentInstrumentId / dunning) and account credit
-- (AccountCredit ledger, which replaces Stripe's customer balance).

-- CreateEnum
CREATE TYPE "PaymentProvider" AS ENUM ('CHECKOUT_COM');

-- CreateEnum
CREATE TYPE "CreditReason" AS ENUM ('REFERRAL_REWARD', 'MANUAL_ADJUSTMENT', 'REFUND');

-- AlterTable: User
ALTER TABLE "User" DROP COLUMN "stripeCustomerId";
ALTER TABLE "User" ADD COLUMN "providerCustomerId" TEXT;

-- AlterTable: PricingPlan
ALTER TABLE "PricingPlan" DROP COLUMN "stripeProductId";
ALTER TABLE "PricingPlan" DROP COLUMN "stripePriceId";
ALTER TABLE "PricingPlan" ADD COLUMN "provider" "PaymentProvider" NOT NULL DEFAULT 'CHECKOUT_COM';
ALTER TABLE "PricingPlan" ADD COLUMN "providerProductId" TEXT;
ALTER TABLE "PricingPlan" ADD COLUMN "providerPriceId" TEXT;

-- AlterTable: Promotion (discounts are now applied by our own engine)
ALTER TABLE "Promotion" DROP COLUMN "stripeCouponId";
ALTER TABLE "Promotion" DROP COLUMN "stripePromotionCodeId";

-- AlterTable: Subscription — we own the billing cycle now
ALTER TABLE "Subscription" DROP COLUMN "stripeSubscriptionId";
ALTER TABLE "Subscription" DROP COLUMN "stripePriceId";
ALTER TABLE "Subscription" ADD COLUMN "provider" "PaymentProvider" NOT NULL DEFAULT 'CHECKOUT_COM';
ALTER TABLE "Subscription" ADD COLUMN "providerSubscriptionId" TEXT;
ALTER TABLE "Subscription" ADD COLUMN "providerPriceId" TEXT;
ALTER TABLE "Subscription" ADD COLUMN "interval" "PriceInterval";
ALTER TABLE "Subscription" ADD COLUMN "cancelAtPeriodEnd" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "Subscription" ADD COLUMN "canceledAt" TIMESTAMP(3);
ALTER TABLE "Subscription" ADD COLUMN "paymentInstrumentId" TEXT;
ALTER TABLE "Subscription" ADD COLUMN "failedPaymentCount" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "Subscription" ADD COLUMN "lastPaymentAt" TIMESTAMP(3);

CREATE UNIQUE INDEX "Subscription_providerSubscriptionId_key" ON "Subscription"("providerSubscriptionId");
CREATE INDEX "Subscription_status_currentPeriodEnd_idx" ON "Subscription"("status", "currentPeriodEnd");

-- CreateTable: AccountCredit (append-only ledger; replaces Stripe customer balance)
CREATE TABLE "AccountCredit" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "currency" TEXT NOT NULL,
    "reason" "CreditReason" NOT NULL,
    "description" TEXT,
    "sourceType" TEXT,
    "sourceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AccountCredit_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AccountCredit_userId_currency_idx" ON "AccountCredit"("userId", "currency");
-- Idempotency: one grant per (sourceType, sourceId, user).
CREATE UNIQUE INDEX "AccountCredit_sourceType_sourceId_userId_key" ON "AccountCredit"("sourceType", "sourceId", "userId");

ALTER TABLE "AccountCredit" ADD CONSTRAINT "AccountCredit_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
