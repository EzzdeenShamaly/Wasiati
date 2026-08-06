# Agent instructions

**Read `CLAUDE.md` in this directory first — it is the single agent guide for this repo.**

Non-negotiables (full detail + rationale in `CLAUDE.md` and `docs/DECISIONS.md`):

- Source-of-truth precedence: `docs/DECISIONS.md` → `WASIATI_SPEC.md` **v2.2** → `Wasiati
  Prototype.dc.html` (both in `C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\`)
  → handoff/token docs. The repo's `DESIGN_BRIEF.md` is historical.
  Design package = `DV2.x`, spec doc = `v2.x` — **DV2.1 ships spec v2.2**; not a contradiction.
  The old `Downloads\Wasiati Ship Package\` path no longer exists; `DV2.0` is superseded.
- Payments = **Stripe** under a UAE entity (DECISIONS §12; Checkout.com is gone). Card
  processor **only** — our own subscription engine stays behind `PaymentProviderPort`;
  Stripe Billing is deliberately unused. Webhooks at `POST /payments/webhook`.
- KYC = **Sumsub** (US/CA) + **Nafath** (KSA, server-enforced 403). ⚠️ §13 calls for **Stripe
  Identity** instead, but **it is not built** — no adapter exists. ID verification **IS a
  gate**: sealing and owner-signing both require a `VERIFIED` user (§13).
- Fonts: Fraunces / Public Sans / **IBM Plex Sans Arabic** (AR UI, §13 — deliberately replaces
  Almarai; the old "never IBM Plex" rule is dead) / **Amiri** (Qur'anic) — bundled, never
  runtime-fetched.
- Plans: **no Basic on sale** (§13 supersedes §10) — but only because the seed deactivates it,
  not by any code rule; `Will.tier` still defaults to BASIC.
- School picker ships **Jumhūr vs Ḥanafī** only; §13's five-school picker + classical radd is
  **not built yet**.
- Burial copy says **"contributions"**, never "installments" (legal requirement).
- Fara'id arithmetic: `backend/src/wills/sharia-calculator.ts` is the authority, not the
  prototype.
- `.dc.html` design files are **not code** — never build, lint, import, or "fix" them; read
  them read-only as the pixel/copy reference.
