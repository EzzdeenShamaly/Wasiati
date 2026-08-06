# Wasiati — Agent Instructions

Wasiati (وصيتي, wasiati.com) is a Sharia-compliant digital will & legacy platform: Flutter
client (iOS/Android/web) + NestJS/Prisma/Postgres backend, launching in **KSA, Qatar, Canada,
US** (each region a physically separate deployment/DB for data residency). Bilingual EN + AR
with full RTL.

## Where the truth lives — precedence order

When sources disagree, the higher one wins. **Do not "fix" the code to match a lower source.**

1. **`docs/DECISIONS.md`** — owner-approved deviations from the design package. Highest
   authority. Never revert these to match the design (several exist for legal reasons).
2. **`<HANDOFF>\WASIATI_SPEC.md`** (**v2.2**) — product behavior: flows, plans, fara'id
   rules, acceptance criteria.
3. **`<HANDOFF>\Wasiati Prototype.dc.html`** — pixel-level look & copy: exact
   hex/px/radius values and every EN/AR string.
4. `WASIATI_HANDOFF.md` / `DESIGN_TOKENS.md` (same folder) — tokens & component specs.
5. Repo `DESIGN_BRIEF.md` — **historical context only**; superseded where it conflicts.

`<HANDOFF>` = `C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\`
— the **DV2.1** package of record (DECISIONS §13 + addendum). It holds 8 flat files; there is
no `WASIATI_SPEC.md` anywhere inside this repo, so don't go looking for one.

**Two version schemes — do not conflate.** Design package = `DV2.x` (folder name); spec
document = `v2.x` (its own header). **DV2.1 ships spec v2.2** — both numbers are current and
are not a contradiction.

Never take specs from the superseded **DV2.0** package at
`C:\Users\raed1\Downloads\Wasiati.com DV2.0\` (it still exists on disk, and its
`_SUPERSEDED design_handoff_wasiati\` subfolder is older still). The path
`C:\Users\raed1\Downloads\Wasiati Ship Package\` that older docs cite **no longer exists**.

## Hard facts (agents keep getting these wrong)

These describe the **shipped code**, verified against source on 19 Jul 2026. Where the code
deliberately lags an owner decision, the bullet says so — **`docs/DECISIONS.md` still wins as
the decision**, but do not assume it is built.

⚠️ **This file is a summary and it goes stale. `docs/DECISIONS.md` is the authority, and the
CODE is the truth about what ships.** When they disagree, believe the code, then DECISIONS,
then this file — never the other way round. A stale line here once told agents that identity
verification gated sealing when the opposite was true and recorded in §17; acting on it would
have broken sealing for every user. If a bullet here contradicts what you can read in the
source, the bullet is wrong: fix it as you pass.

- **Payments: Stripe**, under a UAE entity (**DECISIONS §12** — Checkout.com is removed
  completely; zero references remain in live code). Stripe is the **card processor only**:
  Checkout Sessions, `off_session` PaymentIntents for renewals, refunds, and
  signature-verified webhooks — all behind `PaymentProviderPort` (`StripeProvider` is the
  sole implementation). **Stripe Billing is deliberately NOT used** — the subscription
  engine, billing cycle, promos and credit ledger are our own code (`SubscriptionsService`
  runs a daily cron over `currentPeriodEnd`); prices are ad-hoc `price_data`, never Stripe
  Price/Product objects. Webhooks at `POST /payments/webhook` (no global prefix — this route
  is correct, do not "fix" it). Env: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
  `PAYMENT_RETURN_HOSTS`. Prices stay **per region in local minor units**, charged exactly as
  displayed, never FX-converted at charge time (**§2**).
  *Trap:* `backend/src/payments/checkout-region.spec.ts` is about **pricing regions**, not
  Checkout.com — the filename is a false lead.
- **Identity/KYC: Sumsub** (US/CA document rail, behind `IdentityProviderPort`) + **Nafath**
  (KSA, server-enforced 403 for non-KSA — **§7–8**). ⚠️ **The code LAGS §13 here:** §13
  replaces Sumsub with **Stripe Identity**, but **no Stripe Identity adapter exists** — the
  only implementations are `SumsubIdentityProvider` and `UnconfiguredIdentityProvider`.
  Build it before claiming it; don't write docs or code that assume it's there.
- **ID verification is a BADGE, not a gate** (**§17**, 17 Jul — supersedes the §13 reading
  this file used to carry). There is deliberately **no** `assertIdVerified` on the signing or
  sealing path: grep it, and the only hit in `wills.service.ts` is the comment explaining its
  absence. Identity stays optional in v1 so KSA can launch before Nafath government
  onboarding completes.
  🚨 **Do NOT "fix" this by adding the gate.** Not hypothetical: commit `b2bcb84` did exactly
  that, following spec §3 (a LOWER source than DECISIONS), and it blocked every `UNVERIFIED`
  user — the default state — from sealing a will at all. §17 exists to record undoing it.
  Reintroducing it requires a NEW DECISIONS entry, not a reading of the spec.
- **Plans: no Basic is on sale** (**§13**, superseding §10). `seed-pricing.ts` seeds
  **Standard** and **Premium** (each `ONE_TIME` + `MONTH` + `YEAR`; annual = 10× monthly) and
  **Ultimate** (US/CA only, subscription-only), then deactivates every `BASIC` row; the
  catalog and checkout read `active: true` only.
  ⚠️ **Basic is excluded by SEED DATA, not by an invariant.** `isPurchasable()` returns true
  for BASIC, the admin plan DTO accepts it, and `createPlan` defaults `active: true` — so an
  admin-created BASIC row **would sell**. (Contrast Ultimate + `ONE_TIME`, which IS
  code-blocked in `plan-rules.ts`.) The `BASIC` enum is also **live, not a fossil**:
  `Will.tier` defaults to BASIC and a free user can create a BASIC will, locked immutable.
  ⚠️ The **landing storefront is hardcoded and stale** — it advertises prices the catalog
  does not have, including an Ultimate "once" that checkout structurally refuses.
- **Region:** geo-IP **preselects**, the user **confirms** at registration (DECISIONS §3 —
  deliberate deviation from the spec's "no region question"). Residency binds to the
  confirmed value; `assertResidency()` enforces it.
- **Fonts:** Fraunces (display) / Public Sans (body) / **IBM Plex Sans Arabic** (Arabic UI) /
  **Amiri** (Qur'anic & hadith only). All bundled in `app/apps/wasiati/assets/fonts` — never
  fetch fonts at runtime. **§13 deliberately adopted IBM Plex Sans Arabic in place of
  Almarai** (`WasiatiType.arabicFamily`); the old "never IBM Plex" rule is **dead**, and
  Almarai is no longer the Arabic UI face.
- **Will flow:** guided steps → a required **Review** page → seal. Premium+ first choose
  **Ameen (AI) or Guided form**; Premium+ get a **video step before Review**. "Words for my
  family" caps at **5,000 chars** (spec §3 wins over the handoff's 2,000) — `sanitizeWillText`
  trims to 5,000, though the DTO's `@MaxLength(8000)` means a direct API caller sending
  5,001–8,000 chars is **silently truncated** rather than rejected.
- **School picker: `Jumhūr` vs `Ḥanafī` only** — that is what ships
  (`create_will_screen.dart`), because contemporary radd collapses the five `Madhhab` values
  the backend accepts into just two distinct computations. ⚠️ **The code LAGS §13 here:**
  §13 calls for a **five-school picker** with **classical radd** (Maliki/Shafi'i surplus to a
  bayt al-mal line) and dhawu al-arham under Hanafi. The five-school l10n strings already
  exist and are code-generated but **no widget references them**; `RADD_SCHOOLS` still
  implements the superseded §0 contemporary-radd position, and `cwMadhhabNote` ships that
  position as **user-facing copy**. Treat this as unbuilt, and see §13 before touching it.
- **Fara'id engine:** `backend/src/wills/sharia-calculator.ts` is the **authority** — the
  prototype's engine has the al-Gharrāwayn bug (DECISIONS §1). Take copy and basis strings
  from the prototype; never its arithmetic.
- **Burial (Ultimate):** prepaid **escrow contributions** toward today's price — say
  **"contributions", never "installments"** (consumer-credit law, DECISIONS §6). No
  inflation math anywhere. Refund terms must be stated.
- **Referral:** DECISIONS §5 scheme (friend 10% discount on annual/one-time; referrer 2.5%
  first-year value as account credit, 100-day hold, $500/yr + 100-payout caps).
- **Copy:** 1,287 ARB keys (EN + AR, verified in parity 22 Jul 2026 — the "531" this bullet
  used to claim was long stale) are the compile-time fallback; the admin Content tab's
  overrides merge over them at launch (DECISIONS §4). Add new strings to **both** ARB files.
  Fiqh-bearing copy is not an ordinary string edit — it needs a DECISIONS entry (§22).

## The design files are NOT code

`.dc.html` files use a proprietary runtime (`<x-dc>`, `<sc-if>`, `<sc-for>`, `{{ }}` holes).
Editors and linters will report hundreds of errors on them — **that is expected, not a defect**.

- Never import, build, lint, "fix", or copy their constructs. Read them **read-only** by path
  from Downloads. They are gitignored (`*.dc.html`) as a backstop — keep it that way.
- To build a screen: grep `data-screen-label="…"` in `Wasiati Prototype.dc.html` (~4,000
  lines), read ~200 lines around the match, and **transcribe exact values** — hex, px, radii,
  weights. The `class Component extends DCLogic` block near line ~2470 holds demo state,
  the `t` EN/AR copy objects, and reference logic.
- **Never read** `Wasiati Prototype.html` or `VISUAL REFERENCE all screens.html` (compiled,
  ~1.4 MB, minified) — open them in a browser to *see* intended behavior instead.

## Flutter fidelity rules

- **Never invent a style.** Every value comes from the prototype or
  `app/packages/design_system` (`WasiatiColors`, `context.tokens`, `WasiatiType`,
  `WasiatiCard`, `WasiatiSeal`, `WasiatiUpgradePrompt`). No raw hex in screens, no default
  Material look, no Tailwind-style approximations.
- **RTL:** use `EdgeInsetsDirectional`, `BorderRadiusDirectional`, `AlignmentDirectional`,
  `inline-start/end` thinking everywhere. Verify every screen in **both** locales; AR uses
  Arabic-Indic numerals (٠١٢…) and line-height ≥ 1.7.
- **No pasted symbol glyphs.** Characters like ✦ ⅛ ⅓ › ✓ from the web prototype render as
  tofu (□) in the bundled fonts — use `Icons.*`, drawn widgets, or localized text (two
  commits already purged these; don't reintroduce them).
- One screen at a time: build, render it against the prototype open in a browser, fix, then
  move on. Remaining gaps are tracked in `docs/DESIGN_FIDELITY.md` and
  `docs/FLUTTER_REVIEW.md`.

## Commands

```bash
./scripts/dev-bootstrap.sh              # infra up + migrate + seed + backend/.env
cd backend && pnpm start:dev            # API on :4000, Swagger at /docs
cd app && melos bootstrap               # Flutter workspace
cd app/apps/wasiati && flutter run -d chrome --web-port=3000
flutter analyze && flutter test         # in app/apps/wasiati
cd backend && pnpm test                 # backend unit tests
```

Demo logins: `demo@wasiati.test` / `DemoPass12345` (comped Ultimate) ·
`admin@wasiati.test` / `AdminPass123456` (admin). Emails land in Mailhog :8025.
