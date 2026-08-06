# Wasiati — code review pack

Snapshot of `feat/checkout-qatar-faraid` for external review. Sharia-compliant digital will
platform: Flutter web/mobile app, NestJS + Prisma + PostgreSQL backend, static landing page.

**No secrets are in this archive.** It is built from git-tracked files only; `backend/.env`
is gitignored and excluded. `backend/.env.example` shows the shape without values. There is
no `.git` directory, so no history and no chance of a secret surviving in an old commit.

## Layout

| path | what |
|---|---|
| `backend/src/` | NestJS API — auth, wills, payments, identity, portal, death claims |
| `backend/prisma/` | schema + migrations |
| `app/apps/wasiati/` | the Flutter app |
| `app/packages/design_system/` | tokens, theme, components |
| `landing/` | static marketing page |
| `docs/DECISIONS.md` | **read this first** — owner-approved decisions, numbered, some superseding others |

## Running it

`scripts/dev-bootstrap.sh` brings up Postgres/Redis/MinIO/Mailhog via Docker, migrates and
seeds. Backend `npm run start:dev` (:4000). App `flutter run -d chrome --web-port=3000` — the
port matters, `PASSKEY_ORIGIN` and CORS are pinned to it.

Tests: `cd backend && npx jest` (906 tests, 74 suites) and `cd app/apps/wasiati && flutter test`.

**One gotcha that will waste your time otherwise:** the Flutter integration tests
(`test/*_integration_test.dart`) talk to a live backend and share a per-IP rate limit, so they
fail when run as a batch and pass individually. That is by design — a 429 hard-fails rather
than silently skipping, because a suite that reports green without executing is worse than a
red one. Run them one file at a time.

## Where to look first

**`backend/src/wills/sharia-calculator.ts` is the fara'id arithmetic authority.** It divides
real estates and its output is printed into sealed legal documents. It is treated as
quarantined: changes require owner sign-off, not just review.

Two guards exist specifically to make changes to it provable, and they are worth understanding
before reading the engine:

- `sharia-engine-fingerprint.spec.ts` — hashes all five madhhab settings over 3,586 heir
  configurations. Any arithmetic change flips a hash. The header documents the required
  process when it fails (regenerate the full 18,216-configuration snapshot, diff it, confirm
  every moved line was meant to move) and calls out that JUMHUR and HANAFI are LIVE, so a diff
  there is a question about already-sealed documents rather than a test to re-baseline.
- `sharia-calculator.spec.ts` — the doctrinal cases, plus tests asserting that MALIKI, SHAFII
  and HANBALI are *intentional* aliases of JUMHUR under contemporary application.

## Recent work worth reviewing closely

The last two days were a fara'id correctness pass. Each of these changes what a will says:

1. **A sole surviving spouse takes the whole estate.** Previously a widow took her eighth and
   75% went to bayt al-māl — a treasury that does not exist in the jurisdictions served, so
   that share would lapse into intestacy and a secular court would divide it. See DECISIONS
   §21 and the commit for the reasoning.
2. **Shares stored to six decimals, not two.** A sixth was stored as 16.66, short by 0.007% of
   the estate. `Decimal(5,2)` → `Decimal(9,6)`.
3. **The grandmother question was ambiguous** and always built a *maternal* grandmother, so a
   paternal grandmother received a sixth the father was owed.
4. **Impossible families are refused** — two fathers used to become one father and a will that
   still certified 100%. Note wives are a *limit* (four), not a singleton.
5. **A will nobody inherits under will not seal** — that case is dhawu al-arḥām, which the
   engine does not model and cannot without choosing between school methodologies.

## Known gaps — deliberate, not oversights

- **Dhawu al-arḥām (distant kindred) are not modelled at all** — no daughter's children,
  sister's children, maternal uncles, maternal grandfather. Implementing them requires
  choosing between ahl al-tanzīl and ahl al-qarābah, which is a doctrinal decision awaiting a
  qualified scholar. Sealing such an estate is refused rather than guessed.
- **Al-mushtaraka** — the engine excludes full brothers under every school (the Ḥanafī/Ḥanbalī
  answer). The classical schools split 2–2 here, so the current picker label is contestable
  for that one family shape. Flagged in DECISIONS §21 for scholar review.
- **The madhhab picker offers two options, not five**, because measured over 18,216
  configurations Mālikī, Shāfiʿī and Ḥanbalī produce byte-identical output to Jumhūr under
  contemporary radd. Three extra labels computing the same numbers would be decoration.
- **TOTP is not implemented.** `User.mfaSecret` exists in the schema and is never written.
- **Stripe is not activated** — the Identity adapter is written and tested but falls back to
  Sumsub until real credentials land, and logs a warning saying so.
- **The PDF preview loads pdf.js from unpkg** at runtime (pinned to 3.2.146). That is the
  `printing` package's behaviour; vendoring it is on the list.

## A pattern worth knowing about this codebase

The recurring defect here has not been wrong algorithms — it is **capability built on the
server and never wired to a screen**, so the test suite stays green while the feature does not
exist for a user. Recent examples: the will preview, both export format toggles, the
phone-verification endpoints, and the delete control. When reviewing, it is worth asking of
any backend feature: what calls this?

Tests that drive real screens are preferred over tests that assert a widget exists, for the
same reason.
