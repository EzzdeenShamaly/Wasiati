-- Admin Content tab: user-facing strings (EN + AR), published live, with an
-- append-only audit of every edit.

CREATE TABLE "ContentString" (
  "key"       TEXT NOT NULL,
  "valueEn"   TEXT NOT NULL,
  "valueAr"   TEXT NOT NULL,
  "note"      TEXT,
  "published" BOOLEAN NOT NULL DEFAULT true,
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "ContentString_pkey" PRIMARY KEY ("key")
);
CREATE INDEX "ContentString_published_idx" ON "ContentString" ("published");

CREATE TABLE "ContentRevision" (
  "id"        TEXT NOT NULL,
  "key"       TEXT NOT NULL,
  "valueEn"   TEXT NOT NULL,
  "valueAr"   TEXT NOT NULL,
  "editedBy"  TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ContentRevision_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "ContentRevision_key_createdAt_idx" ON "ContentRevision" ("key", "createdAt");
ALTER TABLE "ContentRevision"
  ADD CONSTRAINT "ContentRevision_key_fkey" FOREIGN KEY ("key")
  REFERENCES "ContentString" ("key") ON DELETE CASCADE ON UPDATE CASCADE;
