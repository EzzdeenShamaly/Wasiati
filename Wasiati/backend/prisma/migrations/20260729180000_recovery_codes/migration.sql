-- Single-use backup codes for MFA recovery.
--
-- MFA is mandatory on every password login, and the only free second factor is now an
-- authenticator app. Without an offline escape hatch, losing that device locks the owner
-- out of the one document their family needs — and there is no support path that can
-- verify them without re-creating the impersonation risk MFA exists to stop.
--
-- codeHash is a SHA-256 of the normalised code and is UNIQUE so verification is a single
-- indexed read, not a bcrypt compare against every code a user holds. Spent rows are kept
-- (usedAt) rather than deleted: an unexplained use is how someone learns of a breach.

CREATE TABLE "RecoveryCode" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RecoveryCode_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "RecoveryCode_codeHash_key" ON "RecoveryCode"("codeHash");
CREATE INDEX "RecoveryCode_userId_idx" ON "RecoveryCode"("userId");

ALTER TABLE "RecoveryCode" ADD CONSTRAINT "RecoveryCode_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
