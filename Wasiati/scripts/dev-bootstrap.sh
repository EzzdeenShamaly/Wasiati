#!/usr/bin/env bash
# One-command local bootstrap for Wasiati.
#
#   ./scripts/dev-bootstrap.sh
#
# Brings up Postgres + Redis + MinIO + Mailhog, waits for them, runs the DB
# migrations, seeds an admin + pricing + demo data, and prints how to start the app.
# Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▸ Starting infrastructure (postgres, redis, minio, mailhog)…"
docker compose -f infra/docker-compose.yml up -d

echo "▸ Waiting for Postgres to be healthy…"
until docker exec wasiati-postgres pg_isready -U wasiati -d wasiati_us >/dev/null 2>&1; do
  sleep 1
done
echo "  postgres ready"

cd backend

if [ ! -f .env ]; then
  echo "▸ No backend/.env — creating one from .env.example with dev defaults…"
  cp .env.example .env
  # Fill the values the local stack needs so the app boots (env validation requires
  # a real SESSION_SECRET; MinIO + Mailhog point at the compose services).
  {
    echo ""
    echo "# --- injected by dev-bootstrap.sh ---"
    echo "SESSION_SECRET=$(head -c 48 /dev/urandom | base64 | tr -d '/+=' | head -c 48)"
    echo "REGION=US"
    echo "NODE_ENV=development"
    echo "OTP_DEV_ECHO=true"
    echo "STORAGE_BUCKET=wasiati-us"
    echo "STORAGE_ENDPOINT=http://localhost:9000"
    echo "STORAGE_FORCE_PATH_STYLE=true"
    echo "STORAGE_ACCESS_KEY_ID=wasiati"
    echo "STORAGE_SECRET_ACCESS_KEY=wasiati-dev-secret"
    echo "ZAKAT_GOLD_PRICE_PER_GRAM_USD=9500"
    echo "ADMIN_EMAIL=admin@wasiati.local"
    echo "ADMIN_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)Aa1!"
  } >> .env
  echo "  wrote backend/.env (admin password is in that file — grep ADMIN_PASSWORD)"
fi

echo "▸ Installing backend deps (pnpm)…"
pnpm install --prefer-offline >/dev/null

echo "▸ Applying migrations…"
pnpm exec prisma migrate deploy

echo "▸ Seeding admin + pricing + demo…"
pnpm run seed:admin || true
pnpm run seed:pricing || true
pnpm run seed:demo || true

cat <<'DONE'

✅ Local stack is up.

  Backend :  cd backend && pnpm start:dev        (http://localhost:4000, docs at /docs)
  App     :  cd app/apps/wasiati && flutter run -d chrome --web-port=3000
  Mail    :  http://localhost:8025               (verify/reset emails land here)
  MinIO   :  http://localhost:9001               (user: wasiati / pass: wasiati-dev-secret)

  OTP_DEV_ECHO=true, so witness/trustee/MFA codes are returned in the API response —
  you can walk the whole signing flow without Twilio. Drop in real STRIPE_*
  (STRIPE_SECRET_KEY / STRIPE_WEBHOOK_SECRET) / TWILIO_* / SUMSUB_* keys in
  backend/.env when you have them.
DONE
