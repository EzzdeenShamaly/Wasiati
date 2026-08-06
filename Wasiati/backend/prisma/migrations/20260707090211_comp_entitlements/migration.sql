-- AlterTable
ALTER TABLE "User" ADD COLUMN     "compExpiresAt" TIMESTAMP(3),
ADD COLUMN     "compGrantedBy" TEXT,
ADD COLUMN     "compTier" "SubscriptionTier";
