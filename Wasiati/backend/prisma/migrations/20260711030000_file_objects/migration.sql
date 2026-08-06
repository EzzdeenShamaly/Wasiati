-- Uploaded file records: ownership + size, for the per-user storage quota and
-- key→download resolution. Confirmed after the client's direct-to-storage PUT.

CREATE TABLE "FileObject" (
  "id"          TEXT NOT NULL,
  "userId"      TEXT NOT NULL,
  "kind"        TEXT NOT NULL,
  "key"         TEXT NOT NULL,
  "contentType" TEXT NOT NULL,
  "sizeBytes"   INTEGER NOT NULL,
  "createdAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FileObject_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FileObject_key_key" ON "FileObject" ("key");
CREATE INDEX "FileObject_userId_idx" ON "FileObject" ("userId");

ALTER TABLE "FileObject"
  ADD CONSTRAINT "FileObject_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
