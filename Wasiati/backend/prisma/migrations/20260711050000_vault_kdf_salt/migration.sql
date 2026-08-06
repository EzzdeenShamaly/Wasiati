-- Per-user random PBKDF2 salt for the vault KEK (replaces the deterministic
-- userId-derived salt). Nullable so existing rows backfill lazily on first fetch.
ALTER TABLE "Vault" ADD COLUMN "kdfSalt" TEXT;
