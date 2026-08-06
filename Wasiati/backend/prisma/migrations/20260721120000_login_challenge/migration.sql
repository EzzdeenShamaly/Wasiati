-- LoginChallenge: the short-lived proof that the PASSWORD step of login succeeded.
--
-- POST /auth/login/resend-mfa is authenticated by this and nothing else — the request
-- carries no userId, no email, no destination, so there is no identifier on the endpoint
-- to enumerate and an unauthenticated caller can cause zero SMS.
--
-- Opaque + hashed rather than a JWT: the app signs access tokens with the one
-- SESSION_SECRET and JwtStrategy accepts any payload signed with it (no `typ` check), so a
-- signed challenge JWT would be a purpose-confusion bug waiting for a missed guard. This
-- mirrors RefreshToken / EmailVerificationToken / PasswordResetToken exactly.
--
-- No consumedAt column: one challenge covers every resend inside its 15-minute window.
-- Abuse is bounded by the per-destination cooldown and hourly cap in AuthService, not by
-- burning the token — a user who needs two codes is a normal user, not an attacker.

CREATE TABLE "LoginChallenge" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoginChallenge_pkey" PRIMARY KEY ("id")
);

-- The lookup key. Unique so the hash alone resolves one row without a userId to scope it —
-- the same reason ClaimAccessToken.tokenHash is unique.
CREATE UNIQUE INDEX "LoginChallenge_tokenHash_key" ON "LoginChallenge"("tokenHash");

CREATE INDEX "LoginChallenge_userId_idx" ON "LoginChallenge"("userId");

-- Supports the expired-row sweep in DataRetentionService.
CREATE INDEX "LoginChallenge_expiresAt_idx" ON "LoginChallenge"("expiresAt");

ALTER TABLE "LoginChallenge" ADD CONSTRAINT "LoginChallenge_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
