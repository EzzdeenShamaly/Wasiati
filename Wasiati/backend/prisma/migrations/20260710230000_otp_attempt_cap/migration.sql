-- OTP brute-force hardening: count failed guesses per code and burn it after a few,
-- so a 6-digit code cannot be exhausted within its TTL.

ALTER TABLE "OtpCode" ADD COLUMN "attempts" INTEGER NOT NULL DEFAULT 0;
CREATE INDEX "OtpCode_destination_purpose_idx" ON "OtpCode" ("destination", "purpose");
