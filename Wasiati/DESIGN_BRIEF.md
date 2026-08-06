# Wasiati — Design Brief & Build State

> ⚠️ **SUPERSEDED for design & behavior.** The approved design now lives in
> `C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\`
> (`WASIATI_SPEC.md` **v2.2** + `Wasiati Prototype.dc.html`), with owner-approved deviations recorded in
> `docs/DECISIONS.md`. See `CLAUDE.md` for the precedence order. This brief is kept
> as historical context; where it conflicts with those sources, **they win**.

> **Purpose:** a current, single-source reference for designing the Wasiati UI. It
> describes what the app *is*, the brand, every screen and its states, the
> navigation model, the data each screen shows, and the known design gaps.
> The app is built and functional (Flutter + NestJS); this brief is what the
> **visual/UX design** should be built against. Last updated for the current build
> (22+ commits; all Phase‑1 product flows implemented, payments + KYC wired).

---

## 1. Product in one paragraph

Wasiati is a **Sharia‑compliant digital will & legacy platform** for **iOS, Android,
and web** (one Flutter codebase), launching in **KSA, Canada, and US**. A user
creates a religiously‑correct will (fixed inheritance shares computed automatically
+ a free "one‑third" for personal bequests), adds witnesses and trustees, stores
secrets in an encrypted vault, verifies their identity (KYC), optionally plans
burial costs, and subscribes via Checkout.com. On death, a trustee submits a claim that an
admin reviews and releases. It must feel **dignified, trustworthy, calm, and
Islamic** — this is an end‑of‑life product handling money, family, and faith.

**Platforms:** phone‑first, but **must be genuinely responsive on tablet & desktop
web** (a current gap — see §8). RTL/Arabic support is required for KSA.

---

## 2. Brand direction

**Palette (no pure black anywhere):**

| Token | Hex | Use |
|---|---|---|
| Parchment | `#ECE3D0` | dominant light background |
| Parchment light | `#F5EFE1` | raised surfaces / cards |
| Parchment deep | `#E2D6BC` | sunken / borders |
| Bottle green | `#2F4A3D` | primary brand, primary buttons |
| Green soft | `#4A6B5A` | hover / secondary green |
| Green tint | `#DCE5DE` | subtle chips / fills |
| Brass gold | `#A87B33` | genuine warm **highlight** (focus rings, accents, badges) — not sparse trim |
| Gold soft / deep | `#C9A45E` / `#8A6222` | gold scale |
| Ink navy | `#1C2333` | **typography + fine accents only**, never a large field |
| Success / warning / danger / info | `#2F7D5B` / `#B4791F` / `#9E3B2E` / `#3A5673` | semantic (muted, never neon) |

Direction: **parchment + soft bottle green carry the weight; brass‑gold is a real
warm highlight; ink‑navy is for type.** Warm, paper‑like, heritage feel.

**Typography:**
- **Fraunces** — display/headings (warm, literary serif)
- **Public Sans** — body/UI
- **Almarai** — Arabic UI text (RTL); **Amiri** (Naskh) for Qur'anic/sacred text only
  *(IBM Plex Sans Arabic is legacy — do not use for new work)*

**The Seal (signature mark):** an **eight‑point geometric seal** (Rub‑el‑Hizb
motif — two overlapping squares). It is both the **brand mark** and a **status
indicator** used throughout, with five states: `idle`, `locked`, `sealed`,
`witnessed`, `verified` (each a color + inner glyph: dot / padlock / padlock /
check / check). Wills, vault items, claims, and KYC all use it to show progress.

**Tone:** dignified, reassuring, plain‑spoken; Islamic but not ornate‑to‑a‑fault;
Arabic wordmark **وصيتي** alongside "Wasiati".

---

## 3. Users, roles & tiers

**Roles:** `USER` and `ADMIN`. Admins get a full **Admin** area and **bypass all
paywalls** (for demo/support). Admins can also **comp** any account to a tier
(demo access without paying).

**Plans** (prices are **admin‑editable at runtime**, region‑specific — one one‑time plan +
three subscriptions, each billable **monthly or annually**; `docs/DECISIONS.md` §10):
- **Basic** — one‑time purchase; the immutable "buy your will once" product.
- **Standard** — will + witnesses/trustee + **encrypted vault (5 items)**.
- **Premium** — + unlimited vault + **video legacy messages** + **Ameen AI intake**.
- **Ultimate** (US/CA only) — + **burial pre‑planning** (prepaid escrow contributions).

**Feature flags gate the UI** (`immutableWill`, `unlimitedEdits`, `vault`,
`videoMessages`, `aiIntake`, `burialPlanning`). Non‑entitled users hit a graceful
**"upgrade" prompt**; admins/comped accounts see everything. Design needs: locked/
upgrade states for gated features, and a "COMPED / ADMIN — full access" badge.

---

## 4. Navigation model

Signed‑in app is wrapped in a **responsive nav shell**:
- **Wide (≥900px):** left **NavigationRail** (Home, Wills, Vault, Burial, Identity,
  Plans + admin: Admin, Users, Claims) with the Seal at top and sign‑out at bottom.
- **Narrow:** bottom **NavigationBar** with 4 primary + a **"More"** sheet.

> ⚠️ **This shell exists but needs a proper responsive design.** Today the inner
> screens still use phone‑width max‑widths, so desktop looks like a centered phone
> column. **Designing a real responsive layout system (rail + wide content, multi‑
> column where sensible) is a priority.** See §8.

**Auth screens** (welcome/login/register/etc.) sit **outside** the shell (no nav).

---

## 5. Screen inventory

### Auth (no nav shell)
1. **Splash** — Seal + spinner while resuming session.
2. **Welcome** — Arabic wordmark وصيتي + "Wasiati" + tagline; "Create your will" / "I already have an account". *(Marketing landing lives here.)*
3. **Register** — email, region (**geo‑IP preselects, user confirms** — binds data residency, see `docs/DECISIONS.md` §3), phone (optional), password (≥10). Auto‑signs in; sends verification email.
4. **Login** — designed method order: **Nafath** (only when in KSA, RECOMMENDED) → **Passkey** (Face ID / Windows Hello) → **Google / Apple** → "Continue with email" (email+password revealed on tap). A Microsoft endpoint exists in the backend but is **not part of the designed UI**.
5. **Verify‑MFA** — 6‑digit SMS code (shown only when MFA enabled).
6. **Forgot‑password** → confirmation; **Reset‑password** (from emailed link, ≥10 chars).
7. **Verify‑email** — auto‑verifies from emailed link; resend fallback.

### Signed‑in (in nav shell)
8. **Dashboard / Home** — greeting, user chips (region, role), **entitlement card** (tier + feature list + ADMIN/COMPED badge).
9. **Wills list** — cards with Seal status (locked/sealed) + "Create will".
10. **Create will** — add heirs (relation + name) with **live Sharia share preview** that recomputes on every edit; disclaimer text + accept checkbox; create.
11. **Will detail** — Seal status (locked/sealed); **Sharia shares** table; **bequests** (free‑third, add, 1/3 cap enforced); **Witnesses** and **Trustees** sections (add name+phone, status, "send code").
12. **Vault** — passphrase **unlock** screen → list of secrets (labels), reveal/add/delete. All encryption is client‑side (server stores ciphertext only). Gated to Standard+.
13. **Burial planning** — **today's price, prepaid escrow *contributions*** (3/5/10‑yr periods; the word "installments" is forbidden — consumer‑credit law, `docs/DECISIONS.md` §6); **NO inflation math**; "Zero interest · zero profit" stated; cumulative progress chart; "request a real quote". Gated to Ultimate (US/CA).
14. **Identity / KYC** — status‑aware (Unverified/Pending/Verified/Rejected) with Seal; **optional in v1** (trust badge, never a gate on sealing). **Region‑routed:** US/CA users verify via **Sumsub** (hosted); **KSA users use Nafath** — enter national ID, then the app shows a **number to match in the Nafath app** and polls until verified. Two visually distinct verify states to design (hosted‑redirect vs. number‑match wait screen). Both drive the same status.
15. **Plans & pricing** — live catalog: plan cards (name, price, `/mo` or one‑time, features, "Most popular" badge), **offer banners**, **promo‑code** checker, "Choose {plan}" → **Checkout.com** hosted payment, "Manage billing" panel (plan, card, invoices, cancel).

### Admin (nav shell, admin only)
16. **Admin console** — tabs: **Plans** (edit price live), **Promotions** (create/delete), **Offers**.
17. **Admin users** — **stat charts** (users by region / ID status / role) + **data table** (email, phone, region, role, ID status, email‑verified, comp tier, last IP, joined). *(Charts + table exist; need visual design.)*
18. **Death‑claim queue** — claims list with status; actions: start review, approve, reject (reason), release.

### Backend‑ready, **UI not built** (design + build needed)
- **Assets inventory** — region‑aware asset entry on a will (Canada: RRSP/TFSA/RESP/RRIF; US: 401k/IRA/Roth/529; KSA: GOSI/end‑of‑service; plus generic real‑estate/bank/vehicle/business).
- **AI conversational intake** (Premium) — chat that extracts heirs/assets (needs a Gemini key).
- **Video legacy messages** (Premium) — record/upload (needs media storage; production phase).
- **Sign‑in buttons** on the Login screen — **Passkey, Google, Apple, Microsoft**. Backend endpoints (`/auth/login/{google,apple,microsoft}` + passkey ceremony) and the Flutter `AuthController` methods exist; what's left is (a) the **visual buttons** (design) and (b) each provider's **platform SDK + credentials** (Google client IDs, Apple Service ID/key, Azure app registration) before it goes live. Passkey needs no external credentials and works today.

---

## 6. Reusable components to design

Seal (5 status variants, any size) · primary/secondary/text buttons (green / outlined
/ gold text) · inputs (filled parchment, gold focus ring) · cards (parchment‑light,
hairline border, 18px radius) · chips/badges (region, role, feature, "Most popular",
"COMPED") · plan/pricing card · offer banner · stat tiles · **charts** (donut + bar,
brand palette) · **data table** (admin users) · list rows with Seal + status +
action · dialogs (add heir/bequest/promo/secret) · bottom‑sheet ("More" nav) ·
snackbars (success green / danger brick) · empty states (Seal + message) · loading
(spinner / linear).

---

## 7. Content & i18n

- **Bilingual:** English + **Arabic (RTL)**; the app must flip layout direction for
  Arabic. Wordmark وصيتي. **Almarai** for Arabic UI runs; **Amiri** for Qur'anic text.
- **Tone:** "Assalamu alaikum" greeting is used; keep copy respectful, clear, and
  legally careful (there's a required legal **disclaimer** before will creation).
- **Money:** region currencies — USD, CAD (`CA$`), SAR (`SAR`).

---

## 8. Known design gaps (please prioritize)

1. **Responsiveness** — the single biggest gap. Inner screens are phone‑width; need a
   real breakpoint system so tablet/desktop use the space (wider content, multi‑column
   dashboards, side‑by‑side detail panes, the nav rail integrated as a first‑class layout).
2. **Visual system** — current UI is functional/plain (default Material). Needs the full
   brand treatment: parchment textures, Fraunces headings, the Seal used expressively,
   gold highlights, elevation/shadow language, iconography.
3. **Onboarding / marketing** — welcome + a real landing/marketing surface for web.
4. **Empty & error states**, **skeleton loaders**, **success/celebration moments**
   (e.g., will sealed, identity verified) using the Seal.
5. **Admin dashboards** — charts/table need a designed analytics layout.
6. **Unbuilt screens** (assets, AI intake, video, social sign‑in) need design too.

---

## 9. Technical notes for handoff

- **Frontend:** Flutter (Material 3), Riverpod, go_router, `fl_chart`. Design tokens
  live in `app/packages/design_system` (colors, typography, theme, the Seal painter).
- **Backend:** NestJS + Prisma + Postgres; Swagger/OpenAPI at `/docs` (JSON at
  `/docs-json`) — the full API surface for reference.
- **Demo:** run the app and log in as `demo@wasiati.test` / `DemoPass12345` (comped
  Ultimate, pre‑seeded will + burial) or `admin@wasiati.test` / `AdminPass123456`
  (admin console + users + claims). Sample data is seeded.
