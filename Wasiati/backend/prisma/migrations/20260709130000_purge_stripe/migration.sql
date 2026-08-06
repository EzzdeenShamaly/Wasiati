-- Purge the last Stripe-shaped names now that Checkout.com is the only provider.
--
-- Both are renames, not drops: the enum value and the table hold live rows
-- (processed webhook ids provide replay protection and must not be lost).

-- Stripe Identity is gone; the US/CA rail is now a generic document-KYC vendor.
ALTER TYPE "IdVerificationProvider" RENAME VALUE 'STRIPE' TO 'DOCUMENT';

-- Webhook idempotency is provider-neutral.
ALTER TABLE "ProcessedStripeEvent" RENAME TO "ProcessedPaymentEvent";
ALTER TABLE "ProcessedPaymentEvent" RENAME CONSTRAINT "ProcessedStripeEvent_pkey" TO "ProcessedPaymentEvent_pkey";
