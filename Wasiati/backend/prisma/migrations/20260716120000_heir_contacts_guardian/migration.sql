-- AlterTable
ALTER TABLE "Will" ADD COLUMN     "guardianEmail" TEXT,
ADD COLUMN     "guardianMode" TEXT,
ADD COLUMN     "guardianName" TEXT,
ADD COLUMN     "guardianPhone" TEXT;

-- CreateTable
CREATE TABLE "WillHeirContact" (
    "id" TEXT NOT NULL,
    "willId" TEXT NOT NULL,
    "relation" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "email" TEXT,
    "isMinor" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "WillHeirContact_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "WillHeirContact_willId_idx" ON "WillHeirContact"("willId");

-- AddForeignKey
ALTER TABLE "WillHeirContact" ADD CONSTRAINT "WillHeirContact_willId_fkey" FOREIGN KEY ("willId") REFERENCES "Will"("id") ON DELETE CASCADE ON UPDATE CASCADE;

