# Wasiati — Domain & Integration Architecture

The web front is split into three hosts under `wasiati.com` (all fronted by Cloudflare).
This is the standard SaaS split: a fast, SEO-friendly marketing site separate from the
app, separate from the API.

| Host | Serves | Deploy target |
|---|---|---|
| **`wasiati.com`** | Marketing landing (`landing/`) | Cloudflare Pages (static) |
| **`app.wasiati.com`** | Flutter web app (`app/apps/wasiati`, web build) | Cloudflare Pages / static host |
| **`api.wasiati.com`** | NestJS backend (`backend/`) | Regional server(s) behind Cloudflare |

iOS / Android ship the same Flutter app from the stores (sign-in-first — no in-app
marketing page). The landing's "Create your will" / "Sign in" buttons link to
`https://app.wasiati.com/register` and `/login`.

```
 Visitor ──▶ wasiati.com (landing, static)
                │  "Create your will" / "Sign in"
                ▼
           app.wasiati.com (Flutter web)  ──HTTPS/credentials──▶  api.wasiati.com (NestJS)
 iOS/Android app ─────────────────────────────────────────────▶  api.wasiati.com
```

## Session across subdomains (already wired in code)
`app.` and `api.` are different origins but the **same site** (`wasiati.com`), so the
httpOnly refresh cookie can be shared. Set these on the **API** in production:

```
CORS_ORIGIN=https://app.wasiati.com,https://wasiati.com   # comma-separated; already supported
COOKIE_DOMAIN=.wasiati.com   # shares the refresh cookie across app./api. (AuthCookieService)
COOKIE_SECURE=true           # HTTPS only
```
- CORS runs with `credentials: true` (see `backend/src/main.ts`).
- The refresh cookie is `httpOnly; Secure; SameSite=Lax; Domain=.wasiati.com; Path=/auth`
  — SameSite=Lax is fine because app→api is same-site.
- Mobile clients don't use the cookie (refresh token travels in the body → secure storage).

## Flutter app → API base URL
Point the web/mobile production build's API base at `https://api.wasiati.com`
(dev stays `http://localhost:4000`). This is the app's existing env/flavor config; set it
at the production cutover.

## Cloudflare (production cutover — deferred)
- **TLS:** Full (Strict); **HSTS** on (the landing also sets it via `_headers`).
- **DNS:** `wasiati.com` + `www` → Pages (landing); `app` → Pages (Flutter web);
  `api` → origin server (proxied, orange-cloud).
- **WAF / rate limiting** in front of `api.` (backend also throttles).
- Data residency (KSA/CA/US) is decided at cutover — see ACCOUNTS.md.

## Deploy order at cutover
1. `api.wasiati.com` (backend) with the CORS/cookie envs above.
2. `app.wasiati.com` (Flutter web build) with API base → `api.wasiati.com`.
3. `wasiati.com` (landing) — swap in the final design, verify CTAs point to `app.`.
