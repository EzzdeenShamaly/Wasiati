-- Fara'id shares are stored to SIX decimal places, not two.
--
-- At Decimal(5,2) a sixth was stored as 16.66 rather than 16.666667: the share was short by
-- 0.007% of the estate, which on a $10M estate is roughly $700 per heir, baked into a sealed
-- document. The engine computed the exact fraction and then discarded most of it at the
-- column boundary. Widening is lossless for existing rows.
ALTER TABLE "ShariaShare" ALTER COLUMN "sharePercent" SET DATA TYPE DECIMAL(9,6);
ALTER TABLE "Bequest" ALTER COLUMN "sharePercent" SET DATA TYPE DECIMAL(9,6);
