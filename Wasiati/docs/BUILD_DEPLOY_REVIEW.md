# Build & deploy review — 17 July 2026

Triggered by `npm run start:prod` failing with `MODULE_NOT_FOUND` on `dist/main.js`.
That one symptom sat on top of a chain: fixing it unmasked a production image that
could never boot, which in turn exposed that CI had never once run to completion — so
none of these were being caught. Run against the live backend (Postgres/Redis/MinIO up)
plus a real `docker build` + container boot, and static review. Supersedes nothing in
`DECISIONS.md`; this is the current gap list for the build/packaging/deploy path.

## Fixed in this review
- **Entrypoint path (`28246c1`).** No `nest-cli.json` meant `nest build` fell back to
  plain `tsc`; the `prisma/*.ts` seeds outside `src/` pushed the inferred root up, so the
  entrypoint emitted to `dist/src/main.js` while `start:prod` and the Dockerfile `CMD`
  both hard-code `dist/main.js`. Added `nest-cli.json` + `tsconfig.build.json`
  (`rootDir: ./src`, exclude `./prisma/**`, `tsBuildInfoFile` pinned inside `dist`).
- **Phantom `express` dependency (`28246c1`).** `main.ts` imports `express` and calls
  `express.raw()` for webhook raw bodies but never declared it — it resolved only via npm
  hoisting of `@nestjs/platform-express`'s transitive copy; pnpm's strict layout withheld
  it, so the built server died at `Cannot find module 'express'`. Declared `^4.22.1`
  (the exact version platform-express pins, so it dedupes).
- **Prisma engine could not load in the image (`cee616d`).** The bare `node:20-alpine`
  builder ships no `openssl`, so `prisma generate` failed to detect the OpenSSL version
  (visible all along as a build-log warning) and emitted the `openssl-1.1.x` engine. The
  runtime is Alpine 3.23 with `libssl.so.3`, so the container died at boot with
  `libssl.so.1.1: No such file or directory`. Installed `openssl` in the builder (emits
  the `openssl-3.0.x` engine) and declared it explicitly in the runtime.
- **CI had never completed (`c918222`).** Two independent breaks at the front of the
  `build-test` job, so lint / tsc / migrate / test / build never ran: (1) CI pinned pnpm
  9, but `overrides` lives in `pnpm-workspace.yaml` (a pnpm 10+ location) with no root
  `package.json`, so `--frozen-lockfile` aborted with `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`
  — reproduced (pnpm 9 fails, 10 succeeds on identical files); (2) `pnpm lint` invoked an
  eslint that was declared and configured nowhere. Bumped both jobs to pnpm 10, added
  eslint 9 + typescript-eslint 8 with a flat config, fixed the 4 real lint findings, and
  split `lint`/`lint:check` (CI must not auto-`--fix`).
- **CI never built or booted the image (`3a9b2d2`).** The host-side job was blind to
  packaging defects — which is how the entrypoint bug reached `main`. Added an `image`
  job that builds `backend/Dockerfile`, asserts `/app/dist/main.js` exists where `CMD`
  runs it, and boots the container against Postgres/Redis until it serves. A clean boot
  proves both `express` and the Prisma engine load, covering both classes above.

Verified end-to-end: the production image builds, boots, and serves real rows from
`GET /pricing`; `/docs` is off under `NODE_ENV=production`; `451` tests / `43` suites
pass (unchanged from `e3d877f`); CI's own sequence passes locally on pnpm 10.

## Open — `CLAUDE.md` "Hard facts" are stale vs `DECISIONS.md` (owner reconciliation)
`DECISIONS.md` is the highest authority and self-declares supersession ("this section
wins"). Its §12 (14 Jul) and §13 + DV2.1 addendum (15 Jul) contradict **at least five**
of the "Hard facts (agents keep getting these wrong)" in `CLAUDE.md`, which predates them
and was never updated. This is not an open decision — the owner already decided; it is
`CLAUDE.md` that is stale, and it actively misleads agents (the "Never Stripe" line would
drive an agent to rip out correct, owner-mandated Stripe code — which is how this started).

| `CLAUDE.md` "Hard fact" | `DECISIONS.md` (wins) |
|---|---|
| Payments: Checkout.com; "Never Stripe" | §12 — Stripe under a UAE entity; Checkout.com removed completely |
| Arabic UI font Almarai; "never IBM Plex Sans Arabic" | §13 — IBM Plex Sans Arabic replaces Almarai |
| One-time "Basic" plan + three subscriptions | §13 — no separate Basic; per-tier monthly OR once |
| KYC Sumsub; optional, "never a gate on sealing" | §13 — Stripe Identity (not Sumsub); REQUIRED before seal |
| Fara'id school picker Jumhūr vs Ḥanafī only | §13 — five-school picker |

Not edited here. Reconciling the agent-instruction file against product / design / legal
decisions is an owner call, and a piecemeal one-line fix would wrongly imply the rest is
current. Recommend an owner-approved pass rewriting the `CLAUDE.md` hard-facts to match
`DECISIONS.md` §12–§13, since the highest authority is unambiguous.

**One of these may exceed doc drift:** §13 mandates KYC as a gate on sealing, while
`CLAUDE.md` and the "optional for v1" §0 say the opposite. If the code does not gate
sealing on identity verification, the *code* contradicts the current decision (a real
bug, not a doc issue). Out of scope for this build/deploy pass — flagged only.

## Open — flagged but UNVERIFIED
These came out of an automated audit whose verification stage partially collapsed (a
session limit killed most verifier agents), so they are **plausible, not confirmed** —
treat as leads, not findings:
- **The prod image ships devDependencies.** The builder runs `npm install` with no
  `--omit=dev` and the final stage copies `node_modules` wholesale, so TypeScript, jest,
  webpack, ts-node, the Nest CLI, etc. likely land in the runtime image (size + attack
  surface). Note: the Prisma CLI is a devDependency and is what makes `prisma migrate
  deploy` work in the image, so a naive prune would break migrations — verify before
  fixing.
- **CI and the image resolve dependencies differently.** CI installs via
  `pnpm --frozen-lockfile` (strict, lockfile-pinned); the image builds via `npm install`
  against unpinned `^` ranges with no lockfile in the backend-scoped context (the
  Dockerfile already carries a NOTE about this). So the artifact may contain package
  versions CI never tested, and two builds of one commit may differ. Candidate fix:
  build from the repo root against the workspace lockfile with `pnpm --frozen-lockfile`.

## Environment note
No git remote is configured and `gh` is not installed in the working environment, so
these commits are local-only and the `image` CI job has not executed on a real runner
(its commands are validated locally; GitHub Actions scheduling + service-container
networking are the one unexercised layer). Push the branch and open a PR to run the
full gate.
