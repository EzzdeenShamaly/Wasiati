# Wasiati Backend

NestJS + Prisma + PostgreSQL API for the Wasiati digital legacy platform.

## What's implemented (Phase 1, no Nafath / no MOI API yet)

- **Auth**: email + password + SMS MFA, Google Sign-In, Apple Sign-In, **Passkeys** (Face ID/Touch ID/Windows Hello/Chrome platform authenticator via WebAuthn) — available to all users
- **Wills**: creation, Sharia fixed-share calculator (`sharia-calculator.ts` — the arithmetic authority, see `docs/DECISIONS.md` §1), free-third bequest cap enforcement, tier-gated will limits, shares recompute live from current heir/asset data (never frozen until locked)
- **Assets**: region-aware asset inventory — RRSP/TFSA/RESP for Canada, 401k/IRA/Roth/529 for the US, end-of-service benefits/GOSI for KSA, plus generic types everywhere
- **Witnesses**: add witness → SMS one-time code → digital signature capture (frontend should use `signature_pad`, not a custom canvas)
- **Trustees**: add trustee → SMS confirmation code → confirm
- **Vault**: stores client-encrypted items only (server never sees plaintext) — included in Standard tier and up
- **Death claims**: cert upload → admin review queue → approve (triggers safety-check SMS to the deceased's number) → trustee confirms → release → heir email notification
- **Payments**: **Stripe** hosted Checkout Sessions (UAE entity, `docs/DECISIONS.md` §12 — Checkout.com is removed) — one-time / monthly / yearly cadences for Standard/Premium/Ultimate, signature-verified webhook handling (`POST /payments/webhook`). Stripe is the **card processor only**: Stripe Billing is deliberately unused, and our own subscription engine runs behind `PaymentProviderPort`
- **AI conversational intake** (Premium+): **Gemini** function calling extracts structured will data from a natural conversation, behind an `AiProviderPort` so the model is swappable (`docs/DECISIONS.md` §24); voice input handled client-side via native OS speech-to-text — no custom STT
- **Burial pre-planning** (Ultimate, US/CA only): today's price, prepaid escrow **contributions** — never "installments", no inflation math (`docs/DECISIONS.md` §6); actual booking is a manual admin workflow (calling local mosques), not an automated funeral-insurance integration

## Pricing

Tiers are **Standard / Premium / Ultimate** (no "Basic") — each sold one-time / monthly /
yearly. Prices are **admin-editable at runtime, per region, stored in that region's local
minor units** and charged exactly as displayed (`docs/DECISIONS.md` §2). Reference numbers
live in `WASIATI_SPEC.md` §2 (ship package): Standard SAR 19/mo · 349 once, Premium
SAR 39/mo · 649 once, Ultimate US/CA-only.

## Not yet implemented / Phase 2+

- Nafath OIDC login (pending NIC approval)
- Live MOI death-certificate verification API (pending approval) — currently a manual admin review queue
- Sumsub live wiring for US/CA KYC (`IdentityProviderPort` + service structure ready; needs `SUMSUB_*` keys — vendor decision in `docs/DECISIONS.md` §7)
- Canada Interac-specific identity check
- Bank account auto-import (Plaid for US/CA) — architected for, not built yet
- Per-region deployment automation (Terraform) — comes after a cloud provider is chosen
- Passkey challenge caching (needs Redis wiring — see comments in `passkeys.service.ts`)

## Admin access (death claims, burial quotes)

There's no API path to grant `ADMIN` — that's deliberate, so a compromised account can't self-promote. Create or promote admins with:

```bash
ADMIN_EMAIL=you@wasiati.com ADMIN_PASSWORD=at-least-12-chars npm run seed:admin
```

Run it again with a different `ADMIN_EMAIL` for a second/backup reviewer — every admin gets notified by email when a new death claim or burial quote request comes in, not just one hardcoded address.

## Legal disclaimer

Will creation requires `disclaimerAccepted: true` in the request — the frontend must show the text in `src/wills/disclaimer.ts` and get an explicit checkbox before submitting. Every `Will` row stores which disclaimer version was accepted and when. Bump `CURRENT_DISCLAIMER_VERSION` if the wording changes materially.

## Local setup

```bash
cp .env.example .env
# fill in DATABASE_URL, SESSION_SECRET, STRIPE_SECRET_KEY/STRIPE_WEBHOOK_SECRET, Twilio/Google/Apple keys

npm install
npx prisma migrate dev --name init
npm run start:dev
```

API docs (Swagger) will be at `http://localhost:4000/docs` once running.

## Regional deployment model

This same codebase deploys **once per active region** — `US | CA | KSA` (Qatar was removed as a sales region; launch is single-region per `docs/DECISIONS.md` §25, expanding on demand) — each instance pointed at its own `DATABASE_URL` in that region's data center. There is no shared cross-region database.

`REGION` is **not** a logging label. It is a hard boot gate (`deploymentRegion()` throws before Nest starts if it is missing or invalid) and the residency check (`assertResidency()` refuses to create a user whose region differs from this instance's). It must be a real process env var in production — the image ships no `.env` file, and the gate runs before dotenv loads anyway.

## Docker

```bash
docker-compose up --build
```

This spins up Postgres, Redis, and the backend together for local testing — it represents one region's stack, not the full three-region topology.
