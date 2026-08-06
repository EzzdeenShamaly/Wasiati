# Security sweep — DV2.1 build (15 Jul 2026)

A full static + dynamic pass after the DV2.1 work. Live probes ran against the
local stack with the demo account; static checks grepped the whole `backend/src`
and `app/apps/wasiati/lib`.

## Dynamic (authorized live pentest)

| Probe | Result |
|---|---|
| No-token on protected routes (`/wills`, `/users/me`, `/vault/items`, …) | **401** — pass |
| IDOR — random / other-user will IDs (`/wills/:id`, `/assets`, `/witnesses`, `/pdf`) | **404** — never leaks existence (NotFound, not Forbidden) |
| Privilege escalation — admin routes as a normal user | **403 / 404** — pass |
| SQL-ish payload in login email | **401**, no 500 |
| Login brute-force (10 bad tries) | **429** after 6 — throttled |
| Oversized / XSS bequest name | see finding **F1** |

## Static

- **AuthZ matrix** — every controller is guarded except `auth` and `pricing`
  (correctly public: login/register/forgot + the marketing catalog). All four
  `admin/*` controllers use `@UseGuards(JwtAuthGuard, RolesGuard)` + `@Roles('ADMIN')`
  — role is read from the JWT, never the body.
- **Injection** — no `queryRaw`/`executeRaw` anywhere (all Prisma parameterised).
  The PDF renderer HTML-escapes every interpolated field (`esc()`), so a stored
  `<script>` in a name cannot break out into the Puppeteer document. Flutter renders
  text as text.
- **SSRF** — every server-side outbound `fetch` targets a fixed, config-supplied
  host (Gemini, Sumsub, Nafath). No user-controlled URL is fetched.
- **Secrets** — none hardcoded in `src`; all pulled from `ConfigService`/env.
- **Webhook** — `/payments/webhook` + `/identity/webhook` take the raw body and
  verify the provider signature before trusting the event.
- **Uploads** — no `multer`/`FileInterceptor` on any route; uploads go
  direct-to-storage via a presigned PUT, with the per-kind size cap **and** the
  1 GB per-user quota enforced at presign **and re-checked at confirm** (client
  cannot lie about size).
- **CORS** — origin from `CORS_ORIGIN` env (defaults to `localhost:3000`),
  `credentials: true`; not wildcarded.
- **Rate limiting** — global `ThrottlerGuard` via `APP_GUARD`.

## Findings

### F1 — bequest fields had no length bound  ·  FIXED
`AddBequestDto.beneficiaryName` accepted a 20 KB string and a `<script>` payload
(201). No stored-XSS reached output (PDF escapes, Flutter is safe), but the field
was unbounded → storage/DoS. Added `@MinLength(1)/@MaxLength(120)` on
`beneficiaryName`, `@Max(100)` on `sharePercent`, `@MaxLength(2000)` on `notes`.
Re-tested: oversized now **400**.

### F2 — transitive dependency advisories  ·  PARTIALLY REMEDIATED
`pnpm audit` reported 15 advisories, **all transitive, none on a live request path**.
Pinned patched versions via `pnpm-workspace.yaml` `overrides` (15 → 8):

- `multer >=2.2.0` — clears 4 highs. (Not reachable: no `FileInterceptor`.)
- `js-yaml >=4.1.1` — clears a prototype-pollution moderate.

Accepted (documented) transitive risk:

- **lodash** `_.template` code-injection (high) — **no published fix >4.17.21**, and
  lodash is **never imported** in our code (transitive via `@nestjs/config` +
  `@nestjs/swagger`). Not exploitable.
- **file-type** DoS on malicious media — v21 fix is an **ESM-only major** that would
  break CJS consumers; file-type is **not run on user uploads** (they go direct to
  storage). Deferred to a coordinated dependency bump.
- Remaining low/moderate advisories are dev/build-time only.

## Verify
`npx tsc --noEmit` clean · `npx jest` **369/369** · `flutter analyze` clean.
