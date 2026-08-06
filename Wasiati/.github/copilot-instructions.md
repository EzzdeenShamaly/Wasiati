# Copilot instructions — Wasiati

Read `CLAUDE.md` at the repo root before making changes — it is the canonical agent guide
(source-of-truth precedence, design-file handling, Flutter fidelity rules, commands).

Critical facts that stale docs contradict:

- **Payments: Stripe** under a UAE entity (DECISIONS §12) — Checkout.com is removed
  completely; any Checkout.com mention in docs is legacy. Card processor **only**: our own
  subscription engine stays behind `PaymentProviderPort`, and Stripe Billing is deliberately
  unused. Webhooks at `POST /payments/webhook`.
- **KYC: Sumsub (US/CA) + Nafath (KSA)** — ⚠️ §13 calls for **Stripe Identity** in place of
  Sumsub, but **no adapter exists yet**; don't assume it's there. ID verification **is a
  required gate**: owner-signing and sealing both demand a `VERIFIED` user (§13).
- **Tiers: Standard / Premium / Ultimate** — no "Basic" on sale (§13). Note the `BASIC` enum
  is still live: `Will.tier` defaults to it, and only seed data (not a code rule) keeps a
  Basic plan out of the catalog.
- **Fonts: Fraunces / Public Sans / IBM Plex Sans Arabic (Arabic UI) / Amiri (Qur'anic)** —
  bundled assets only, never runtime font fetches. §13 deliberately adopted IBM Plex Sans
  Arabic in place of Almarai; the old "never IBM Plex" rule is dead.
- **Burial (Ultimate): prepaid escrow "contributions"** — the word "installments" is
  forbidden for legal reasons (docs/DECISIONS.md §6).
- **Fara'id: `backend/src/wills/sharia-calculator.ts` is the authority** — do not port the
  design prototype's arithmetic (it contains a known bug).
- Owner-approved deviations from the design live in `docs/DECISIONS.md` — never "fix" the
  code to match the design where they conflict.

The design reference lives OUTSIDE this repo at
`C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\`
(the **DV2.1** package of record, shipping spec **v2.2**; the older
`Downloads\Wasiati Ship Package\` path no longer exists, and `DV2.0` is superseded).
Its `.dc.html` files are a proprietary
design format, not real HTML — editors will show hundreds of errors on them; that is
expected. Never import, build, lint, or edit them; read them read-only for exact values
(grep `data-screen-label`), and never read the compiled `Wasiati Prototype.html`.
