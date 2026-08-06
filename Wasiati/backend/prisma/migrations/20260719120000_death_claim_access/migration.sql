-- CreateEnum
CREATE TYPE "ClaimRole" AS ENUM ('WITNESS', 'TRUSTEE', 'HEIR');

-- CreateEnum
CREATE TYPE "ClaimTokenScope" AS ENUM ('CLAIM_SUBMIT', 'PORTAL_READ');

-- CreateTable
CREATE TABLE "ClaimAccessToken" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "willId" TEXT NOT NULL,
    "claimId" TEXT,
    "role" "ClaimRole" NOT NULL,
    "scope" "ClaimTokenScope" NOT NULL,
    "subjectPhone" TEXT NOT NULL,
    "subjectEmail" TEXT,
    "heirContactId" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "consumedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ClaimAccessToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "HeirReleaseConfirmation" (
    "id" TEXT NOT NULL,
    "claimId" TEXT NOT NULL,
    "heirContactId" TEXT NOT NULL,
    "confirmedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ipAddress" TEXT,
    "userAgent" TEXT,

    CONSTRAINT "HeirReleaseConfirmation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ClaimAccessToken_willId_scope_idx" ON "ClaimAccessToken"("willId", "scope");

-- CreateIndex
CREATE UNIQUE INDEX "HeirReleaseConfirmation_claimId_heirContactId_key" ON "HeirReleaseConfirmation"("claimId", "heirContactId");

-- AddForeignKey
ALTER TABLE "ClaimAccessToken" ADD CONSTRAINT "ClaimAccessToken_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ClaimAccessToken" ADD CONSTRAINT "ClaimAccessToken_claimId_fkey" FOREIGN KEY ("claimId") REFERENCES "DeathClaim"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "HeirReleaseConfirmation" ADD CONSTRAINT "HeirReleaseConfirmation_claimId_fkey" FOREIGN KEY ("claimId") REFERENCES "DeathClaim"("id") ON DELETE CASCADE ON UPDATE CASCADE;
