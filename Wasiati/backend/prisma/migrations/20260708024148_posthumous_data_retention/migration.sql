-- AlterTable
ALTER TABLE "User" ADD COLUMN     "scheduledPurgeAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "DataPurgeLog" (
    "id" TEXT NOT NULL,
    "deceasedUserId" TEXT NOT NULL,
    "deathClaimId" TEXT,
    "recordsDeleted" JSONB,
    "purgedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DataPurgeLog_pkey" PRIMARY KEY ("id")
);
