# Security sweep — 11 July 2026

A full re-audit after the files/upload pipeline, video, vault import, engine changes,
and bootstrap landed. Run against the LIVE backend (Postgres/Redis/MinIO up) plus
static review and dependency audits. Supersedes nothing in `DECISIONS.md`; this is the
current gap list.

## Fixed in this sweep
- **`FilesService.confirmUpload` quota TOCTOU (MEDIUM).** The used-bytes read and the
  insert were not atomic, so two concurrent confirms could each pass and both commit,
  exceeding the 1 GB quota. Now a Serializable read-sum-write transaction (same fix as
  the bequest cap). Duplicate-key confirm → clean 400. Regression test added.
- **`nodemailer` DoS (HIGH, direct dep).** Bumped 6.9 → 7.0.13 (patches the
  addressparser ReDoS). `tsc` clean; our SMTP usage is unaffected.
- **Vault PBKDF2 iterations 120 000 → 210 000 (MEDIUM).** OWASP-2023 minimum for
  PBKDF2-HMAC-SHA256; materially raises offline-brute-force cost. Round-trip tests pass.
- **Vault salt → per-user random (MEDIUM).** Replaced the deterministic userId-derived
  salt with a random 128-bit salt generated server-side at vault creation (GET
  /vault/kdf), backfilled race-safely, never re-rolled. Not secret; makes each user's
  KEK derivation unpredictable. 4 tests.
- **Orphaned-upload reaper (MEDIUM).** `FilesReaperService` nightly cron lists each
  upload prefix, cross-references confirmed `FileObject` keys, and deletes any object
  older than `UPLOAD_ORPHAN_GRACE_HOURS` (default 24) with no row. This is BETTER than
  a bucket lifecycle rule, which couldn't distinguish a confirmed file from an orphan
  (they share prefixes). 6 tests: reaps old orphans, never touches confirmed or
  in-flight objects, no-op when storage is unconfigured.

## Verified SAFE (live + static)
- **HTTP headers (live).** CSP, `Strict-Transport-Security: max-age=15552000;
  includeSubDomains`, `cross-origin-resource-policy: cross-origin` (PDF embed), nosniff,
  `x-frame-options`, CORS with `vary: Origin` + credentials, and **no `x-powered-by`**.
- **MinIO/storage CORS (live).** A browser `PUT` preflight from `http://localhost:3000`
  returns `Access-Control-Allow-Origin` + `PUT` — the upload works locally out of the
  box. **Prod (S3/R2) needs an explicit bucket CORS rule** (launch checklist).
- **Files pipeline (live probes).** Cross-user `confirm` → `400 "does not belong to
  you"`; 2 GB presign → `400 too large`; `.exe` content-type → `400 unsupported`. Keys
  are namespaced `<prefix>/<userId>/<uuid>`.
- **Tests.** Backend 305 pass; Flutter 69 pass; `flutter build web` compiles with the
  camera + file_picker packages.

## Open gaps (not yet fixed)

### MEDIUM
_(none remaining — both were closed; see "Fixed" below.)_

### LOW / informational
- **6 remaining HIGH npm advisories are transitive and UNREACHABLE in our code paths:**
  `multer` DoS (we expose no multipart endpoints — uploads are direct-to-storage),
  `lodash` `_.template` injection (internal to `@nestjs/config`, never called with our
  input), `nodemailer` raw-option file access (we only send text/html, never `raw`).
  Bump when the parent NestJS packages ship compatible ranges; forcing overrides risks
  breaking NestJS for no reachable gain. `js-yaml` (swagger) ReDoS is dev/docs-only.

## Follow-up sweep — curl + code + deps (same day, after the reaper landed)

Live curl probes against the running backend (:4000) plus a fresh static pass over the
newer modules and a re-audit of dependencies.

### Fixed
- **`nodemailer` bumped 7.0.13 → 9.0.3 (direct dep).** Clears TWO new advisories: the
  `envelope.size` SMTP command-injection (LOW, GHSA-c7w3-x93f-qmm8, patched ≥8.0.4) and
  the message-level `raw`-option file-read bypass (HIGH, patched ≥9.0.1). Both were
  UNREACHABLE in our code (we only ever `sendMail({from,to,subject,text,html})` — never
  `envelope` or `raw`), but nodemailer is ours to own, so we patched rather than waive.
  `tsc` clean; **316/316 backend tests pass** on 9.x.

### Verified SAFE via live curl
- **Headers (re-confirmed on GET /pricing).** Full helmet set: CSP `default-src 'self'`,
  HSTS `max-age=15552000; includeSubDomains`, `cross-origin-resource-policy: cross-origin`,
  nosniff, `x-frame-options: SAMEORIGIN`, referrer `no-referrer`, and **no `x-powered-by`**.
- **CORS.** `Origin: https://evil.com` → **no** `Access-Control-Allow-Origin` echoed;
  `http://localhost:3000` (allow-listed) → echoed with `vary: Origin` + credentials.
- **JWT forgery.** An `alg:none` token (with and without a fake sig) is REJECTED (not
  authenticated). The strategy pins `algorithms: ['HS256']` and signing uses
  `algorithm: 'HS256'` — `alg:none` and alg-confusion are both closed.
- **Auth guards.** `/users/me` with no token and with a garbage token → `401` + clean
  `{message,statusCode}` body (no stack). Validation errors → `400` with class-validator
  messages only. No stack traces leak.
- **Webhooks fail-closed.** `/payments/webhook` with no/bogus signature → `400` (secret
  unset in dev); `/identity/webhook` unsigned → `503` (provider unconfigured). When
  configured, both verify HMAC-SHA256 with `timingSafeEqual` + a length guard
  (constant-time). Swagger `/docs` serves in dev but is gated on `NODE_ENV !== 'production'`.

### Verified SAFE via code review
- **IDOR closed on every will sub-resource.** assets / witnesses / trustees all route
  through `assertWillOwner(willId, ownerId)` which throws `NotFound` (not `Forbidden`, so
  existence isn't leaked) when `will.ownerId !== ownerId`; `remove` re-checks via the
  parent will. Death-claims intentionally uses witness/trustee phone-OTP authz instead.
- **No privilege escalation on `:userId` routes.** `admin/data-retention/*` and
  `payments/admin/burial-plans/:userId` are behind `@UseGuards(JwtAuthGuard, RolesGuard)`
  + `@Roles('ADMIN')`. Every user-scoped module (zakat, checkin, referrals, credits,
  content) derives the actor from `@CurrentUser()` (the JWT) — never a client-supplied id.
- **No mass assignment.** No untrusted `req.body`/dto spread into a Prisma `data:` write.
- **OTP brute-force bounded.** Codes are hashed at rest, TTL-limited, and carry a per-code
  `OTP_MAX_ATTEMPTS = 5` counter that consumes the code after 5 wrong guesses — so rotating
  IPs past the per-IP throttle still can't brute a 6-digit code inside its window.
- **Auth endpoint throttles.** register 5, login 8, verify-mfa 10, verify-email 6,
  resend-verification 3, password/forgot 4, password/reset 5 (per minute).
- **No secrets in git.** `.env` untracked; no `sk_live`/`GOCSPX-`/`AKIA…`/PEM strings in
  `backend/src` or `app/.../lib`. (The chat-leaked Google secret is NOT in code — still
  must be rotated before prod; tracked separately.)

### Open gaps (unchanged)
- **5 high + 10 moderate npm advisories remain — all transitive and UNREACHABLE:** `multer`
  (no multipart endpoints — uploads are direct-to-storage), `lodash` (internal to
  `@nestjs/config`), `js-yaml` (swagger/docs, dev-only), `file-type` (pulled by
  `@nestjs/common`, never called by our code). Fixing needs forced overrides on NestJS's
  tree, which risks breaking NestJS for no reachable gain — bump when the parents ship
  compatible ranges.
- **Flutter (informational):** `js`, `build_resolvers`, `build_runner_core` are marked
  discontinued — all build-time toolchain deps, not shipped in the app bundle; no runtime
  or security impact.
- **`validate-promo` (LOW/informational):** public + unthrottled beyond the global 100/min
  cap, so promo codes are weakly enumerable. Codes grant discounts, not access; the global
  throttler is an adequate backstop. Add a per-route `@Throttle` if promo abuse shows up.
- **`alg:none` returns 400, not 401 (cosmetic).** A forged/malformed token is rejected
  either way; a consistent 401 would be tidier but is not a security issue.

## Prod launch checklist additions (from this sweep)
1. Configure a **CORS rule** on each region's storage bucket allowing `PUT` from the app
   origin (dev MinIO already permits it). This is the ONLY storage config the upload
   pipeline needs — orphan cleanup is handled app-side by FilesReaperService, and the
   vault salt/iterations are already hardened.
