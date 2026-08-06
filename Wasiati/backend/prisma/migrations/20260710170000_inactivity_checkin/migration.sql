-- Inactivity check-in (a death trigger) and the claim-initiation policy (spec §6).

CREATE TYPE "CheckinFrequency" AS ENUM ('MONTHLY', 'QUARTERLY', 'YEARLY');
CREATE TYPE "ClaimInitPolicy" AS ENUM ('TRUSTEE_ONLY', 'HEIRS_WITH_DOCUMENTS', 'BOTH');

-- Off by default: being asked whether you are still alive must be opted into.
ALTER TABLE "User" ADD COLUMN "checkinEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "User" ADD COLUMN "checkinFrequency" "CheckinFrequency" NOT NULL DEFAULT 'QUARTERLY';
ALTER TABLE "User" ADD COLUMN "lastCheckinAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "checkinRemindersSent" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "User" ADD COLUMN "checkinAlertedAt" TIMESTAMP(3);
ALTER TABLE "User" ADD COLUMN "claimInitPolicy" "ClaimInitPolicy" NOT NULL DEFAULT 'BOTH';
