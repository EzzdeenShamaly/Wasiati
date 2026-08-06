-- CreateEnum
CREATE TYPE "GraveInstallmentStatus" AS ENUM ('ACTIVE', 'MATURED', 'CANCELLED');

-- CreateTable
CREATE TABLE "GraveInstallmentPlan" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "totalAmount" INTEGER NOT NULL,
    "amountPaid" INTEGER NOT NULL DEFAULT 0,
    "status" "GraveInstallmentStatus" NOT NULL DEFAULT 'ACTIVE',
    "maturesAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GraveInstallmentPlan_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "GraveInstallmentPlan_userId_idx" ON "GraveInstallmentPlan"("userId");

-- AddForeignKey
ALTER TABLE "GraveInstallmentPlan" ADD CONSTRAINT "GraveInstallmentPlan_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
