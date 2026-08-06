-- Idempotency for identity (Sumsub) webhooks: stop a captured, correctly-signed
-- "verified" webhook from being replayed to defeat a KYC revocation.

CREATE TABLE "ProcessedIdentityEvent" (
  "id"          TEXT NOT NULL,
  "status"      TEXT NOT NULL,
  "processedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProcessedIdentityEvent_pkey" PRIMARY KEY ("id")
);
