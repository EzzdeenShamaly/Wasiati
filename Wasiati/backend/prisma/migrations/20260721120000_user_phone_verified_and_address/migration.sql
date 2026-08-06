-- AlterTable
ALTER TABLE "User" ADD COLUMN     "addressArea" TEXT,
ADD COLUMN     "addressCity" TEXT,
ADD COLUMN     "addressCountry" TEXT,
ADD COLUMN     "addressLine1" TEXT,
ADD COLUMN     "addressLine2" TEXT,
ADD COLUMN     "addressPostalCode" TEXT,
ADD COLUMN     "phoneVerifiedAt" TIMESTAMP(3);

