-- Directives beyond the will: financial power of attorney + healthcare directive.
-- Life documents scoped to the USER (not to a will) — they take effect while the
-- owner is alive and are excluded from the exported will PDF. One row per type
-- per user; re-saving re-executes the same document (see schema comment).

CREATE TYPE "DirectiveType" AS ENUM ('POA', 'HCD');
CREATE TYPE "DirectiveStatus" AS ENUM ('DRAFT', 'SIGNED');

CREATE TABLE "DirectiveDocument" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" "DirectiveType" NOT NULL,
    "agentName" TEXT NOT NULL,
    "agentPhone" TEXT NOT NULL,
    "agentEmail" TEXT NOT NULL,
    "wishes" TEXT,
    "status" "DirectiveStatus" NOT NULL DEFAULT 'DRAFT',
    "signedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DirectiveDocument_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "DirectiveDocument_userId_type_key" ON "DirectiveDocument"("userId", "type");

ALTER TABLE "DirectiveDocument" ADD CONSTRAINT "DirectiveDocument_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
