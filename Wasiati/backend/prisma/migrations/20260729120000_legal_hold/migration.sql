-- Legal hold on an estate.
--
-- The posthumous purge is an automated, irreversible destruction job. Contested probate,
-- a will challenge or any preservation obligation is an ordinary event in this domain,
-- and until now nothing could stop the job — the product would destroy the disputed
-- instrument on schedule. That is the shape of spoliation FRCP 37(e) exists for.
--
-- While legalHoldAt is set the purge refuses, indefinitely, regardless of
-- scheduledPurgeAt. Additive and nullable: existing rows are unaffected and unheld.

ALTER TABLE "User" ADD COLUMN "legalHoldAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "legalHoldReason" TEXT;
ALTER TABLE "User" ADD COLUMN "legalHoldBy" TEXT;
