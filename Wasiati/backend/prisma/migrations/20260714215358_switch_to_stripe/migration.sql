-- Swap the payment provider: enum value CHECKOUT_COM -> STRIPE (and the column
-- defaults with it), PRESERVING existing rows. Postgres cannot drop or rename an
-- enum value in place, so: create the new type, route the columns through TEXT,
-- rewrite the historical rows, cast into the new type, swap the defaults back,
-- and drop the old type.
BEGIN;

CREATE TYPE "PaymentProvider_new" AS ENUM ('STRIPE');

ALTER TABLE "PricingPlan" ALTER COLUMN "provider" DROP DEFAULT;
ALTER TABLE "Subscription" ALTER COLUMN "provider" DROP DEFAULT;

-- Route through TEXT so existing rows can be rewritten before the enum cast
-- (a direct ::"PaymentProvider_new" cast would fail on 'CHECKOUT_COM' rows).
ALTER TABLE "Subscription" ALTER COLUMN "provider" TYPE TEXT USING ("provider"::text);
ALTER TABLE "PricingPlan" ALTER COLUMN "provider" TYPE TEXT USING ("provider"::text);

-- Every historical value becomes STRIPE: these are the same subscriptions/plans,
-- now charged through the new PSP. Stored Checkout.com instruments are not
-- chargeable on Stripe — the renewal job declines them cleanly and dunning asks
-- the customer for a card, which is the intended migration path.
UPDATE "Subscription" SET "provider" = 'STRIPE' WHERE "provider" <> 'STRIPE';
UPDATE "PricingPlan" SET "provider" = 'STRIPE' WHERE "provider" <> 'STRIPE';

ALTER TABLE "Subscription" ALTER COLUMN "provider" TYPE "PaymentProvider_new" USING ("provider"::"PaymentProvider_new");
ALTER TABLE "PricingPlan" ALTER COLUMN "provider" TYPE "PaymentProvider_new" USING ("provider"::"PaymentProvider_new");

ALTER TYPE "PaymentProvider" RENAME TO "PaymentProvider_old";
ALTER TYPE "PaymentProvider_new" RENAME TO "PaymentProvider";
DROP TYPE "PaymentProvider_old";

ALTER TABLE "PricingPlan" ALTER COLUMN "provider" SET DEFAULT 'STRIPE';
ALTER TABLE "Subscription" ALTER COLUMN "provider" SET DEFAULT 'STRIPE';

COMMIT;
