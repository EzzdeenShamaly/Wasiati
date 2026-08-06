-- Signature completion certificate (Adobe Sign-style): capture the audit trail per
-- signer, and the witness ID-match state.

CREATE TYPE "IdMatchStatus" AS ENUM ('PENDING', 'MATCHED');

ALTER TABLE "Witness" ADD COLUMN "userAgent" TEXT;
ALTER TABLE "Witness" ADD COLUMN "idMatchStatus" "IdMatchStatus" NOT NULL DEFAULT 'PENDING';

ALTER TABLE "Trustee" ADD COLUMN "ipAddress" TEXT;
ALTER TABLE "Trustee" ADD COLUMN "userAgent" TEXT;
