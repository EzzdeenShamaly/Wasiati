-- CreateEnum
CREATE TYPE "WillStatus" AS ENUM ('DRAFT', 'SIGNED', 'WITNESSED', 'SEALED');

-- AlterTable
ALTER TABLE "DeathClaim" ADD COLUMN     "submittedByRole" TEXT;

-- AlterTable
ALTER TABLE "Will" ADD COLUMN     "requiredWitnesses" INTEGER NOT NULL DEFAULT 2,
ADD COLUMN     "sealedAt" TIMESTAMP(3),
ADD COLUMN     "signatureData" TEXT,
ADD COLUMN     "signedAt" TIMESTAMP(3),
ADD COLUMN     "signedIp" TEXT,
ADD COLUMN     "status" "WillStatus" NOT NULL DEFAULT 'DRAFT';
