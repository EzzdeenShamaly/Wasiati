-- Split the claim-upload budget in two, because the two operations bound different things.
--
-- CLAIM_UPLOAD_OPERATION_CAP was 2 and BOTH presign and confirm consumed from it, so a
-- token bought exactly one presign plus one confirm. A refund existed only for a presign
-- that threw. But the client's PUT to storage happens BETWEEN the two server calls: when it
-- drops, the server never hears about it and there is nothing to refund. The claimant
-- retries, the second presign spends the last slot, the PUT succeeds, and confirm is
-- refused — no certificate stored, and every further attempt refused at presign.
--
-- presign only hands out a write URL; confirm is what records a certificate. Counting them
-- separately lets a retry cost a presign instead of the whole link, while keeping the real
-- invariant — one death certificate per token — exact.
--
-- Backfill: existing rows have a combined count. A row that reached the old cap of 2 has
-- almost certainly done both operations, so credit one confirm; anything less has not
-- confirmed. Nothing is deployed, so this only matters for local databases.
ALTER TABLE "ClaimAccessToken" ADD COLUMN "confirmCount" INTEGER NOT NULL DEFAULT 0;

UPDATE "ClaimAccessToken" SET "confirmCount" = 1 WHERE "uploadCount" >= 2;
