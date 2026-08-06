# Wasiati Landing (`wasiati.com`)

The public marketing site — a **static site** (no build step, no framework) so it's
fast, SEO-indexable, and cheap. Deliberately separate from the Flutter app (which lives
at `app.wasiati.com`) — see `../INFRA.md` for the full domain architecture and why.

Built from the exported Claude Design canvases (**6a Landing** / **6d Landing Arabic**):
the "Signed W Seal" logo, the `YOUR WILL, YOUR AMANAH` hero (Cormorant Garamond headline)
with the rotated sealed-will card, the Quran 2:180 + Bukhari/Muslim band, and the
bottle-green "Three steps" section. Light "Parchment" + dark "Night green" with a toggle.

```
landing/public/         # <- Cloudflare Pages output directory (deploy this)
  index.html            # English landing (6a)
  ar/index.html         # Arabic (RTL) landing (6d — verses band sits ABOVE the hero)
  styles.css            # brand tokens + responsive layout; mirrors app/packages/design_system
  theme.js              # light/dark toggle (blocking in <head>, no flash; CSP script-src 'self')
  _headers              # security headers + caching (Cloudflare Pages)
  robots.txt
```

## Local preview
Any static server works, e.g.:
```
cd landing/public && python -m http.server 8080   # then open http://localhost:8080
```
For local end-to-end testing against the dev app, temporarily change the
`https://app.wasiati.com/...` links in `index.html` / `ar/index.html` to
`http://localhost:3000/...`.

## Deploy to Cloudflare Pages
1. Cloudflare Dashboard → **Workers & Pages → Create → Pages → Connect to Git** (this repo).
2. Build settings:
   - **Build command:** *(none)*
   - **Build output directory:** `landing/public`
3. Custom domain: add **`wasiati.com`** (and `www` → redirect to apex).
4. `_headers` (HSTS, CSP, etc.) is applied automatically by Pages.

## Swapping in the Claude Design landing
When the exported design (`.dc.html` + assets) lands, replace `index.html` / `ar/index.html`
and drop assets alongside. Keep: the `<meta>`/OG tags, the `hreflang` links, and the CTA
hrefs pointing to `https://app.wasiati.com/register` and `/login`. Update `_headers` CSP if
the design pulls in new external hosts (fonts/images).
