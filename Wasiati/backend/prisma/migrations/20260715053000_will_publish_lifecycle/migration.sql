-- AlterEnum
ALTER TYPE "WillStatus" ADD VALUE 'SUPERSEDED';

-- DropForeignKey
ALTER TABLE "Asset" DROP CONSTRAINT "Asset_willId_fkey";

-- DropForeignKey
ALTER TABLE "Bequest" DROP CONSTRAINT "Bequest_willId_fkey";

-- DropForeignKey
ALTER TABLE "DeathClaim" DROP CONSTRAINT "DeathClaim_willId_fkey";

-- DropForeignKey
ALTER TABLE "ShariaShare" DROP CONSTRAINT "ShariaShare_willId_fkey";

-- DropForeignKey
ALTER TABLE "Trustee" DROP CONSTRAINT "Trustee_willId_fkey";

-- DropForeignKey
ALTER TABLE "Witness" DROP CONSTRAINT "Witness_willId_fkey";

-- AlterTable
ALTER TABLE "Will" ADD COLUMN     "publishedAt" TIMESTAMP(3),
ADD COLUMN     "revisionOfId" TEXT,
ADD COLUMN     "supersededAt" TIMESTAMP(3),
ADD COLUMN     "unpublishedAt" TIMESTAMP(3);

-- AddForeignKey
ALTER TABLE "Will" ADD CONSTRAINT "Will_revisionOfId_fkey" FOREIGN KEY ("revisionOfId") REFERENCES "Will"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Asset" ADD CONSTRAINT "Asset_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShariaShare" ADD CONSTRAINT "ShariaShare_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Bequest" ADD CONSTRAINT "Bequest_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Witness" ADD CONSTRAINT "Witness_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Trustee" ADD CONSTRAINT "Trustee_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DeathClaim" ADD CONSTRAINT "DeathClaim_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

