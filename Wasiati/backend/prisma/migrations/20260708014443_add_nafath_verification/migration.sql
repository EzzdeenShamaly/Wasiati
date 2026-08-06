-- CreateEnum
CREATE TYPE "IdVerificationProvider" AS ENUM ('STRIPE', 'NAFATH');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "idVerificationProvider" "IdVerificationProvider";

-- CreateTable
CREATE TABLE "NafathVerification" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "nationalId" TEXT NOT NULL,
    "transId" TEXT NOT NULL,
    "random" TEXT,
    "status" "VerificationStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "NafathVerification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "NafathVerification_transId_key" ON "NafathVerification"("transId");

-- CreateIndex
CREATE INDEX "NafathVerification_userId_idx" ON "NafathVerification"("userId");

-- AddForeignKey
ALTER TABLE "NafathVerification" ADD CONSTRAINT "NafathVerification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
