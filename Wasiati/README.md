# Wasiati — Monorepo

Sharia-compliant digital will & legacy platform (iOS + Android + web), launching in KSA / QA / CA / US.

- **Client:** Flutter (one codebase → iOS, Android, web) — Riverpod + Freezed, go_router.
- **Backend:** NestJS + Prisma + PostgreSQL, hardened for production.
- **API contract:** typed Dart client **generated from the backend's OpenAPI spec**.

> This build overrides the original build plan's Next.js/Expo/Turborepo frontend choice: the entire
> client is Flutter. See `../.claude/plans/…` for the full staged plan.

## Layout
```
wasiati/
├─ backend/            NestJS + Prisma (pnpm)
├─ app/                Flutter workspace (Melos)
│  ├─ apps/wasiati/    the application (flavored dev/staging/prod)
│  └─ packages/
│     ├─ api_client/     OpenAPI-generated Dart client
│     └─ design_system/  brand tokens, theme, fonts, Seal widget
├─ infra/              docker-compose (dev) + terraform (placeholder)
└─ .github/workflows/  CI (backend + Flutter)
```

## Prerequisites
| Tool | Version | Notes |
|---|---|---|
| Node.js | 20 LTS | backend + tooling |
| pnpm | 9+ | `corepack enable` or `npm i -g pnpm` |
| Flutter | stable | includes Dart |
| Docker | latest | local infra (postgres/redis/minio/mailhog) |
| git | latest | version control |

## Quick start (local dev)

One command brings up the infra, migrates, seeds an admin + pricing + demo, and
writes a working `backend/.env` (random `SESSION_SECRET`, MinIO + Mailhog wired,
`OTP_DEV_ECHO=true` so SMS codes come back in the API response — no Twilio needed):

```bash
./scripts/dev-bootstrap.sh
```

Then start the two processes:

```bash
# Backend — http://localhost:4000 (Swagger at /docs)
cd backend && pnpm start:dev

# Flutter app — origin must match PASSKEY_ORIGIN / CORS
cd app && dart pub global activate melos && melos bootstrap
cd apps/wasiati && flutter run -d chrome --web-port=3000
```

- Emails (verify / reset) land in **Mailhog** → http://localhost:8025
- Object storage is **MinIO** → http://localhost:9001 (`wasiati` / `wasiati-dev-secret`)
- Drop real `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` / `TWILIO_*` / `SUMSUB_*` keys into
  `backend/.env` when you have them.

Payment webhooks: use the Stripe CLI (`stripe listen --forward-to
localhost:4000/payments/webhook`) or your own tunnel pointed at `POST /payments/webhook`.
Signatures are verified against `STRIPE_WEBHOOK_SECRET`.

### Required local `.env` overrides (backend)
```
PASSKEY_RP_ID=localhost
PASSKEY_ORIGIN=http://localhost:3000
REDIS_URL=redis://localhost:6379
CORS_ORIGIN=http://localhost:3000
```

## Regions & data residency
Each region (KSA/QA/CA/US) runs its **own** backend + database + S3 bucket + SES sender. Never point one
region's `DATABASE_URL` at another region's database. FCM push carries **metadata only**.
