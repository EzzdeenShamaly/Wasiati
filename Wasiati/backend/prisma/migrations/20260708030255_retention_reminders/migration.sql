-- AlterTable
ALTER TABLE "Trustee" ADD COLUMN     "email" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "retentionRemindersSent" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "Witness" ADD COLUMN     "email" TEXT;
