# Decisions

Where the shipped implementation intentionally differs from the design package. Originally
written against `Wasiati Design Package/` (`WASIATI_SPEC.md` v2.1, `WASIATI_HANDOFF.md`,
`CLAUDE.md`), confirmed with the owner on 10 July 2026. The design package remains the source
of truth for copy, layout and flows; these are the deliberate exceptions.

> **Current package of record (16 Jul 2026):** `C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\`
> — **DV2.1**, shipping **`WASIATI_SPEC.md` v2.2** (see §13 + addendum). Design package = `DV2.x`,
> spec doc = `v2.x`; DV2.1 ships spec v2.2, which is not a contradiction. The v2.1 spec and the
> `Downloads\Wasiati Ship Package\` path above are **historical** — that path no longer exists.
> Dated headings below are kept verbatim as a decision record; read each with its addenda.

---

## 0. Go-live decisions (owner, 11 July 2026)

Resolved directly with the owner ahead of launch:

- **Will flow:** guided steps → a required **Review** page → seal. Premium/Ultimate
  choose **Ameen (AI) or Guided form** at the start; Standard goes to the form.
  Premium+ get a **video step before Review** (record via webcam/mic, or upload).
- **Uploads:** strict file-type allow-list; **1 GB per user**; beyond that the user
  emails us for a secure upload link (no self-serve overage).
- **Personal message ("Words for my family"):** cap **5,000 characters** (spec §3
  wins over the handoff's 2,000). Enforced on the Flutter counter and the backend DTO.
- **Māliki/Shāfiʿī fara'id:** default to **contemporary radd** — surplus returns to
  the heirs, not bayt al-māl (the majority view today, per the deep research). For the
  heirs we model this makes Māliki/Shāfiʿī identical to Jumhūr, so the school picker is
  **Jumhūr vs Ḥanafī**. `BAYT_AL_MAL` remains only for a truly unclaimable surplus
  (e.g. a lone spouse with no other heir), in every school.
- **Launch:** ~~all four regions at once (US/CA/KSA/QA)~~ **SUPERSEDED by §25** — one
  region (`ca-central-1`) serving every market; Qatar was later removed as a sales
  region entirely (commit `8a277c8`).
- **ID verification:** **optional for v1** — a trust/verified badge, never a hard gate
  on sealing. Lets KSA launch before Nafath government onboarding completes.
- **Object storage provider:** deferred ("table for now"). Uploads keep the honest 503
  until a bucket is wired; MinIO is used locally via the bootstrap.

---

## 1. The fara'id engine is ours, not the prototype's

`CLAUDE.md` says to port the prototype's inheritance math "faithfully". We do not.

The prototype computes **husband + mother + father as 50 / 33.3 / 16.7**. This is the
al-Gharrāwayn (ʿUmariyyatān) case; the correct division is **50 / 16.7 / 33.3** — the
mother takes a third of the *residue after the spouse*, not a third of the estate.
ʿUmar's ruling and all four schools agree. `WASIATI_SPEC.md` §10 reports "all pass"
because it never tests that case.

`backend/src/wills/sharia-calculator.ts` passes **11 of the spec's 12 §10 acceptance
results unmodified**, gets al-Gharrāwayn right, and additionally models consanguine
and maternal siblings, nephews, cousins, and grandfather *muqāsama* — none of which
the prototype has.

**The prototype is the specification for copy, basis strings and the school options.
Our engine is the authority for the arithmetic.**

Outstanding: Maliki/Shafiʿi/Hanbali schools, `bayt al-mal` as its own line (spec §4),
and dhawu al-arḥām under Hanafi. Only the Maliki bayt al-mal case currently fails.

## 2. Prices are per-region and local — never converted at charge time

`CLAUDE.md` says admin sets USD and the client converts via the prototype's `fromUSD()`
table (`SAR 3.75, CAD 1.36, EUR 0.92 …`). `WASIATI_HANDOFF.md` §5 instead says
"region catalog, admin-editable prices". We follow the handoff.

A hardcoded rate for a **floating** currency (CAD, EUR, GBP) means the amount charged
drifts from reality and cannot be reconciled against the PSP. Prices are therefore
stored per region in that region's minor units and charged exactly as displayed.

`convertToFallbackMinor()` exists only for the narrow case where a region's currency is
not enabled on the Checkout.com account. It converts at the currency's **fixed USD peg**
and **throws for any currency without one** rather than guess.

## 3. Region: geo-IP preselects, the user confirms

The spec removes the region question ("region/currency from IP"). Region determines
**which database holds the user's personal data** — regions are physically separate
deployments for data residency — and IP is wrong under VPN, travel and corporate proxies.

Geo-IP supplies the default so the form feels effortless; the user confirms it, and
residency binds to the **confirmed** value. `assertResidency()` rejects a mismatched
write at registration and OAuth sign-in.

## 4. Copy: ARB is the default, admin Content overrides it

The handoff says "all copy is served from the backend — no hardcoded strings". Fully
runtime-served copy means a blank first paint, an offline failure mode, and the loss of
compile-time key checking.

The 531 ARB keys (complete in EN + AR) stay as the compile-time **fallback**; the admin
Content tab's overrides are fetched at launch and merged over them.

## 5. Referral programme

Supersedes `WASIATI_SPEC.md` §2 (which said the referrer earns 2.5% of the first year,
capped at 100 payouts/year) and the earlier `$5-to-both-sides` implementation.

| | |
|---|---|
| **Friend gets** | 10% off at checkout — a discount, not credit |
| **Eligible plans** | Annual or one-time only. Monthly never qualifies. |
| **Referrer earns** | 2.5% of the friend's **first-year value** (annual price, or one-time price) |
| **Paid as** | Account credit in our own ledger. No cash payouts, so no payout rails, KYC or tax reporting. |
| **Hold** | Credit is **visible immediately, spendable after 100 days** — covering the refund/chargeback window |
| **Cap A (per referrer)** | $500-equivalent per calendar year. The referral that crosses it is paid up to the ceiling; after that, further referrals earn nothing. |
| **Cap B (programme)** | 100 payouts per calendar year (`REFERRAL_YEARLY_CAP`) |
| **Past either cap** | Recorded as `CAPPED`, never silently dropped |

Notes:

- The friend's benefit is a **discount rather than credit**, and is only offered on
  plans that already carry a one-year commitment. That makes "no cancellation before a
  year" structural — there is nothing to claw back.
- Referrer and friend are **always in the same region** (regions are separate
  databases), so the commission never needs an FX conversion.
- The commission basis is the plan's committed first-year value, **independent of how
  the friend funded it** — paying with account credit must not shrink someone else's
  commission. A purchase fully covered by credit still qualifies, since the provider
  never sees it and no webhook fires.
- A refund reverses only the **referrer's** credit (append-only reversing entry). The
  friend had a discount, so there is nothing to reverse on their side.

## 6. Burial (Ultimate, US/CA) is prepaid escrow, not installments

The design sells burial "at today's price, zero-interest installments (3/5/10 yrs)".
Lending at 0% is still consumer credit in the US and Canada — state/provincial licences,
Reg Z disclosure. So the product is restructured, not the pricing:

- The customer **prepays contributions** toward a grave reserved today with a local
  mosque. Money in advance is not lending, so no credit licence.
- Contributions are the **customer's own money, held in trust and refundable**. They are
  not revenue until the service is delivered.
- **Death mid-plan:** the reservation and today's price stand; the family settles the
  remaining balance before burial. The plan does NOT self-complete — a guaranteed
  benefit funded by contributions would be preneed *insurance*, which needs an insurer.
- **Death where burial is free** (e.g. KSA): the contributions are **returned to the
  family** in full.

Copy must say "contributions", never "installments", and must state the refund terms.

## 7. Identity verification vendor: Sumsub

For US/CA document verification behind `IdentityProviderPort`. Chosen over Persona and
Onfido for MENA + North America coverage, per-verification pricing with no entry
minimum, and immediate sandbox access. KSA/QA continue to use Nafath.

## 8. Nafath is Saudi-only, enforced server-side

Nafath identifies Saudi residents. `NafathService.initiate()` returns **403** for any
non-KSA user, checked before the outbound call to the government API. The client also
hides the CTA (KYC screen by the user's region, login screen by the build's `REGION`),
but the server is the gate.

## 9. Vault quota + will-tier gating (13 Jul 2026)

- **Vault item cap enforced.** `VaultService.addItem` now caps a **Standard** vault at
  **5 items** (spec §2/§5); Premium/Ultimate/admin are unlimited. Enforced in a
  Serializable transaction so two concurrent adds can't both slip past the limit.
- **Will tier clamped to entitlement.** `WillsService.create` no longer trusts the
  client-supplied `tier`; it clamps it DOWN to the user's live entitlement so a BASIC
  payer can't stamp a will STANDARD to dodge the immutability lock. A free user may
  still draft (Premium features stay hard-gated by `FeatureGuard`; entitlement is always
  resolved live, never from `will.tier`).

## 10. Plan structure — one one-time plan + three subscriptions (owner, 13 Jul 2026)

**RESOLVED (owner decision).** The catalogue is **one one-time plan + three subscription
tiers**, each subscription billable **monthly or annually**:

| Plan | Billing | Notes |
|---|---|---|
| **Basic** | one-time | the immutable "buy your will once" product |
| **Standard** | monthly **or** annual | unlimited edits + encrypted vault |
| **Premium** | monthly **or** annual | + AI intake + video legacy (Most popular) |
| **Ultimate** | monthly **or** annual | + burial pre-planning; **US/CA only** |

This intentionally supersedes `WASIATI_SPEC.md` §2's "Standard 349 once / Premium 649 once"
(the one-time option is its OWN plan — Basic — not a Standard/Premium cadence). Annual =
10× monthly (two months free). Referral qualifies on an annual subscription or the
one-time purchase (DECISIONS §5).

**Already correct in code — no migration needed.** `schema.prisma` keeps the `BASIC` enum;
`seed-pricing.ts` seeds BASIC `ONE_TIME` + STANDARD/PREMIUM/ULTIMATE `MONTH`+`YEAR` across
US/CA/KSA/QA (Ultimate US/CA only). The landing site shows the four plans (restored
13 Jul 2026); the earlier "remove Basic" landing change was reverted to match this decision.

## 11. One will per client + one draft (owner, 14 Jul 2026)

A client keeps **at most two wills**, of which **only one may ever leave `DRAFT`**
(be signed/witnessed/sealed). The second is a draft-only working copy.

Enforced server-side in `wills.service.ts`, both inside **Serializable** transactions
so concurrent requests can't slip past the checks:
- `create` — rejects a third will (`count >= MAX_WILLS_PER_OWNER = 2`).
- `signByOwner` — rejects signing when another of the owner's wills is already non-`DRAFT`.

The Flutter wills list mirrors this: the "Create will" button and the "create another"
card disappear at the cap, with a note (`wlCapNote`). The list already labels the first
will "primary" and the rest "additional".

## 12. Payment provider: Stripe, under a UAE entity (owner, 14 Jul 2026)

**Checkout.com is removed completely.** They onboard enterprises only — not startups —
so the company will incorporate in the **UAE** and process cards with **Stripe** there.

Scope of the swap:
- Stripe is the **card processor only** (Checkout Sessions for hosted payments,
  PaymentIntents for renewals, signed webhooks). We deliberately do **not** adopt
  Stripe Billing: the subscription engine, billing cycle, promotions and credit
  ledger remain **our** code behind `PaymentProviderPort`, exactly as before —
  that seam is what made this swap cheap, and it stays.
- `PaymentProvider` enum value `CHECKOUT_COM` → `STRIPE` (migration updates rows).
- Env: `CHECKOUT_*` keys are gone; `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET`
  (return-host allowlist lives on as `PAYMENT_RETURN_HOSTS`).
- §2 stands unchanged: prices stay per-region in local minor units, charged exactly
  as displayed; the fixed-peg fallback now covers a currency not enabled on the
  **Stripe** account.

Any doc that still says Checkout.com is stale — this section wins.

## 13. DV2.0 / spec v2.2 adopted wholesale (owner, 15 Jul 2026)

The owner-supplied package `Wasiati.com DV2.0` (spec v2.2, prototype, tokens) is the
new source of truth — "implement it to the dot." Where v2.2 contradicts earlier
sections, **v2.2 wins**, specifically:
- **Fonts:** Arabic UI font is **IBM Plex Sans Arabic** (v2.2 explicitly replaces
  Almarai). The earlier "never IBM Plex" rule targeted STALE docs; v2.2 makes it a
  deliberate design decision. Amiri stays for Qur'an/hadith. (Supersedes the font
  note in CLAUDE.md/§0-era guidance.)
- **Plans (supersedes §10):** per-tier monthly OR once — Standard SAR 19/mo · 349
  once, Premium SAR 39/mo · 649 once, Ultimate US/CA only; no separate Basic plan.
  Unpaid login lands on the full Plans page before checkout (paywall-first).
- **KYC (supersedes §7):** Nafath (KSA) + **Stripe Identity** elsewhere (not Sumsub).
  Identity verification is REQUIRED before any will can seal (supersedes the
  "optional for v1" go-live decision in §0).
- **Fara'id (supersedes §0 school-folding):** five-school picker (Jumhur default,
  Hanafi/Maliki/Shafi'i/Hanbali); **classical radd** — Maliki/Shafi'i surplus to
  bayt al-mal as its own line; dhawu al-arham fallback under Hanafi; daughters
  alone do NOT block uncles/cousins from the residue.
- **Will lifecycle:** ≤1 published + ≤1 draft (as §11); adds Unpublish (back to
  draft, witnesses notified), Delete and Unpublish behind step-up auth (SMS OTP /
  Face ID) with audit-trail entries; editing a published will re-seals as a revision.
- **Export gate:** the PDF downloads only after 2 witnesses + trustee confirm;
  shares toggle between % and fara'id fractions.

**The ONE deviation (§6 stands, legal):** v2.2's burial copy says "zero-interest
installments" — the word **"installments" remains banned** in user-facing copy for
consumer-credit-law reasons. The 3/5/10-year plans ship exactly as designed, worded
as **"contributions."**

### §13 addendum — DV2.1 (owner, 15 Jul 2026 09:50)

`Wasiati.com DV2.1\Exports\wasiati-dev-handoff` supersedes DV2.0. The owner fixed
the package at source: **"installments" → "contributions" everywhere** (spec §2,
handoff, tokens, and the prototype's own strings — contributionLbl etc.), so the
§13 legal deviation is RESOLVED and the package is implementable verbatim. Also:
landing Qur'an-card spacing and hexagon watermark positions retuned.

---

## 14. Semantic colours are theme-swapped for contrast (owner, 17 Jul 2026)

> **Provenance.** This section was first written by the branch that made the change
> (`2cd0e62`) and signed pending, because nothing in the repo recorded the owner's
> approval of the *deviation* — §14 departs from the DV2.1 prototype's constants, and
> the standing directive is "design to the dot". **The owner approved it on 17 Jul
> 2026** (having reported the symptom, "the font colour is barely readable in dark
> mode"): keep the theme-swapped inks. The signature above is now the owner form. This
> approval covers the addendum below, including its stop-button decision.

The prototype's dark block (`Wasiati Prototype.dc.html`, `body[data-theme="dark"]`)
re-points `--green`, `--tint`, `--btn` and `--goldDeep`, but **not** `--success`,
`--warning`, `--danger` or `--info` — those hold one value across both themes. As
*type* on the night surfaces they fail WCAG AA badly:

| as text | on `nightSurface` | on `parchmentLight` |
| --- | --- | --- |
| `danger` `#9E3B2E` | **2.28:1** | 5.87:1 |
| `success` `#2F7D5B` | **3.08:1** | **4.36:1** |
| `warning` `#B4791F` | **4.17:1** | **3.22:1** |
| `info` `#3A5673` | **2.02:1** | 6.64:1 |

This is the same defect the owner reported as "the font colour is barely readable in
dark mode" for gold. That one was a transcription miss — the prototype *did* swap
`--goldDeep` and the app had copied only the light end. **This one is not:** the
prototype carries the defect, so fixing it is a deliberate deviation from source #3.

**Do not revert these to the prototype's constants to "restore fidelity."**

`WasiatiTokens` gains `dangerInk` / `successInk` / `warningInk` / `infoInk`, mirroring
`goldInk`:

- **dark** ends lighten — `#D57C70` / `#3EA679` / `#DD9C38` / `#7798BB` (5.08 / 5.07 /
  6.50 / 5.11 on `nightSurface`; all ≥4.5 on `nightRaised`, the harder field). Each
  holds its fill's HSL hue and saturation and lifts only lightness, so a state keeps
  its identity across themes.
- **light** ends darken where needed — `successDeep #2B7253` (5.04) and
  `warningDeep #885C18` (5.10). `warning` was the surprise: as light-theme type it
  was a *worse* miss (3.22) than its dark case, and 2.85 on its own chip tint.
  `dangerInk` (5.87) and `infoInk` (6.64) keep their raw constant as the light end,
  so neither needs a `Deep`.

**The split is ink vs. fill, not light vs. dark.** The raw constants remain correct
and are still used for what they were tuned for: snackbar/button fields, chip and
tint backgrounds, 1px borders, the donut chart palette, and the `Seal`'s solid body.
Anything a user *reads* — text, icons, status dots — takes the ink. `theme.dart` also
pins `inputDecorationTheme.errorStyle` to `dangerInk`, since Material would otherwise
default validation copy to `ColorScheme.error`, which is the fill.

Guarded by `app/apps/wasiati/test/theme_contrast_test.dart`.

**`info` gap closed (16 Jul 2026).** The change above was scoped to three colours and
left `info` pinned in that test as a known gap. It was the worst of the four — 2.02:1
on `nightSurface` and 1.80:1 on `nightRaised`, where its status dot missed even the
3:1 bar for a graphical object — and it now has `infoSoft #7798BB` / `infoInk` on the
same terms as the other three, with the pin replaced by a real AA assertion. Its two
type sites take the ink: the SUBMITTED death-claim status dot + label, and the
dashboard witnesses tile. The `Seal`'s witnessed body and the donut palettes are
fills and keep the raw constant.

### §14 addendum — a fill with a label on it is not exempt (owner, 17 Jul 2026, see §14)

The rule above says fills are exempt from the 4.5:1 type bar, and names "snackbar/
button fields" among them. That is too broad, and the success snackbar is where it
breaks: `WasiatiSnack.success` was `onDark #F3ECDC` on a `success #2F7D5B` field —
**4.24:1**, under the bar for body text. The fill is correct *as a fill*; it is the
label on it that misses, which is why the ink/fill split alone did not catch this.

The exemption holds only for fills **nothing is read on** — 1px borders, status dots,
chip and tint backgrounds, donut slices. A fill carrying copy owes the bar for that
copy, and is tuned by what sits **on** it, not what it sits on.

`WasiatiSnack.success` now takes **`successDeep #2B7253`** (4.91:1 under `onDark`).
Reused rather than given its own constant: it is already the dark end of the success
scale, and a dedicated field colour would be the same hex under a second name.
`WasiatiSnack.danger` is unchanged — `danger` already carries `onDark` at 5.72:1.

Not extended to the `Seal`'s verified body or the dashboard checkbox, the other two
places parchment sits on a raw `success`. Those are **glyphs, not copy**: WCAG 1.4.11
sets 3:1 for graphical objects, and they measure 4.24:1 and 4.36:1. Both pinned in
the contrast test so the distinction is recorded rather than re-litigated.

**The record red is an indicator, never a field (17 Jul 2026).** `WasiatiColors.record
#C46B5C` is the same shape of problem, and the only one the rule above cannot solve.
Five of the prototype's six uses of it are dots, a 1.5px border and a 10% tint — fills
nothing is read on, so exempt. The sixth is `wvStop`'s "Stop & save" field (prototype
line 1549), and it carries a label at **3.27:1** under the prototype's own `#F5EFE1`.

**Owner decision (17 Jul 2026): keep the red, make the label read.** A red stop control
is the near-universal recording convention — users read a green stop as "still rolling"
— so `scheme.primary` was the wrong fix even though it read as AA. The raw `#C46B5C`
cannot carry a label (no ink we own clears 4.5 on it: `inkNavy`, the darkest, reaches
only **4.19:1**; `onDark` is 3.18). So the stop button takes **`recordStopField`** — the
record red deepened until `onDark` clears the bar at **4.94:1** — and a **stop-square
icon** carries the affordance under WCAG 1.4.11 (graphical, 3:1) so nothing rests on the
label alone.

`recordStopField` is close to `danger` in luminance — a deeper red is a deeper red — but
it is a warmer terracotta, and the two never share a surface: the record screen shows no
`danger`. The record **dot** stays the prototype's exact `#C46B5C`, unchanged, on all
three "Record video" buttons. `danger` keeps its own job — `wvDelete` ("Delete"), which
is destruction, where "Stop" ends capture and then offers Retake/Use.

The prototype's recording rail (a pulsing `#C46B5C` dot, a gold timer, and the label
"Recording… speak from the heart") is **not** transcribed: the app records on its own
full-bleed camera screen, not the rail, and rebuilding it is a layout job, not a
palette one. Only the label's colour moved here — off `dangerInk` and onto the rail's
own ink at weight 700, which is what the prototype gives it.

---

## 15. The death-claim "safety check" is a delay, not a liveness probe (owner, 17 Jul 2026)

`approveAndSendSafetyCheck` issues an OTP to the deceased owner's phone and stamps
`safetyCheckSentAt`; `release` then refuses until a 72h window
(`DEATH_CLAIM_SAFETY_WINDOW_HOURS`) has elapsed. The code presented this as a fraud
signal — "if the phone's owner responds/uses the app at all after this point, that's
the fraud signal… a real response should **auto-reject the claim**."

**It never did.** No auto-reject exists anywhere in the backend; the phrase appears
only in those comments. Nothing consumes a response, a login, or an app-open. The SMS
goes out and no code path listens. Therefore:

- The ping is **inert for every owner**, not merely for phoneless ones. It pings the
  number and logs delivery. That is the whole of it.
- The 72h window is a **pure time delay**, and always has been.
- An owner with **no phone** is skipped by the ping entirely, yet `safetyCheckSentAt`
  is stamped regardless — so release's gate is satisfied by a check that never
  happened. That is the *visible* instance of a gap that is in fact universal.

Phoneless owners are the common case, not an edge. Phone is optional at registration
(`register.dto.ts`, `@IsOptional()`), never requested on the OAuth signup path, and
**cannot be added later** — `UsersController` exposes only `GET /users/me`, and nothing
outside register ever writes `phone`. Sealing does not require one.

**Decision: document the truth rather than dress it up. Do NOT "fix" this by requiring
a phone, and do not refuse to approve a phoneless owner's claim** — that would strand
those claims with no admin path forward in order to enforce a check that does nothing
even when it passes.

What the spec actually asks, and what actually guards a release:

- The spec requires only **"approve ≠ release; both audited"** (WASIATI_SPEC §6). It
  never mentions a safety check, a ping, a 72h window, or the deceased's phone — those
  are implementation inventions, not transcriptions. The separation of approve from
  release is what §6 wants, and it holds; this decision does not touch it.
- Release stays gated on **human admin review**, the **72h delay**, `will.status ===
  'SEALED'`, and **at least one CONFIRMED trustee** — a separate human, over their own
  SMS code. Those are the real protections, and none of them is a proof-of-life.

So the honest name for the window is a **cooling-off delay before an irreversible
handover**, not a liveness probe. The misleading comments are corrected; behaviour is
unchanged.

**If a real liveness signal is ever wanted**, it means implementing the auto-reject the
old comment only promised — owner activity after `safetyCheckSentAt` rejects the claim
— at which point a phone genuinely matters and the phoneless path needs its own ruling.
That is a feature, not a comment fix, and is deliberately out of scope here.

Pinned by `backend/src/death-claims/death-claims-approve.spec.ts`. **Separate known
bug, not addressed here:** a phoneless owner can seal a will but can then never
unpublish or delete it — both gate on `verifyStepUp`, whose error tells them to "Add
one in your profile first", which no route or screen provides.

---

## 16. The gold CTA is theme-swapped, not brass (owner, 17 Jul 2026)

Applying §14's addendum to the gold "upgrade" button found a defect the prototype
carries and cannot be fixed by re-inking. `WasiatiButtons.goldSolid` was `onDark
#F3ECDC` on a `brassGold #A87B33` field: **3.22:1**. `labelLarge` is 15px/w600
(`typography.dart:56`), below WCAG's 18.66px-bold large-text threshold, so the 4.5:1
bar applies and the 3:1 escape does not.

**`brassGold` cannot be a field under type at all.** Every permitted ink misses on it —
`onDark` 3.22, `parchmentLight` 3.30, `greenDeep` 3.45, and `inkNavy`, the darkest in
the palette, only **4.15**. Only pure black clears (5.55), and black is not a UI colour
here (`colors.dart` preamble). So the field had to move.

**And one gold cannot serve both themes.** Against a night card the label needs a field
luminance ≤ 0.1483, while the 3:1 boundary (WCAG 1.4.11, UI component) needs ≥ 0.1551.
The constraints do not overlap. `goldDeep` everywhere would have fixed the label and
dropped the dark-theme button to **2.51:1** on `nightRaised` — where `create_will`
mounts it — trading unreadable copy for an unfindable button.

So the field takes the two ends `goldInk` already theme-swaps, and the label inverts
with it:

| | field | label | label | boundary |
| --- | --- | --- | --- | --- |
| light | `goldDeep #8A6222` | `onDark` | 4.63:1 | 4.76 card / 4.28 page |
| dark | `goldDeepDark #C9A45E` | `inkNavy` | 6.70:1 | 6.55 card / 5.84 raised |

This **deviates from the design package** and is a visible brand change on the paid
CTA (pricing, burial quote, seal, AI intake, upgrade — 7 call sites). The prototype
ships `background:var(--gold); color:#F5EFE1` — **3.30:1** — on ~8 controls and never
theme-swaps it, so this is not a transcription fix like `--goldDeep` was. **Do not
revert it to `var(--gold)` to restore fidelity.**

The raw constants are used, not `context.tokens.goldInk`: that token is tuned as type
*on* a surface, and this is a field *under* type. Same values today, different jobs —
so `goldDeep` and `goldDeepDark` each now carry two, pinned in `theme_contrast_test.dart`.

**Known gap, not fixed here:** `brassGold` as *type* on `parchmentLight` is still
3.30:1 — already pinned in that test as pre-existing. It is a separate question from
the CTA field and wants its own owner call.

---

## 17. ID verification is a badge, not a gate on sealing — correcting a regression (owner, 17 Jul 2026)

This restates and enforces the §0 go-live decision: **"ID verification: optional for v1
— a trust/verified badge, never a hard gate on sealing. Lets KSA launch before Nafath
government onboarding completes."** It is recorded as its own section because the code
had already drifted away from it once, and the precedence rule (`CLAUDE.md`: "do not fix
the code to match a lower source") is exactly what was violated.

**What went wrong.** `WASIATI_SPEC.md` §3 reads "Identity verification: required once
before any will can seal." That is source #2. Commit `b2bcb84` implemented it literally —
`WillsService.assertIdVerified` threw `ForbiddenException` unless
`idVerificationStatus === 'VERIFIED'`, enforced at BOTH owner-signing and seal — which
**contradicts §0**, the higher owner decision. New users default to `UNVERIFIED`
(`schema.prisma`), ID verification is optional (a badge), and in KSA the Nafath vendor may
not be onboarded at all — the very case §0 exists for. So the gate blocked the core flow
for the **default** user: an unverified owner could draft but never bind a will. The
`seed-demo.ts` users are hand-set `VERIFIED` "so they may seal wills without a live KYC
round-trip" — a workaround that only existed because the gate blocked everyone else. The
Flutter client never gated on this, so client and server disagreed; the client was right.

**Decision: the gate is removed.** `assertIdVerified` and its two call sites are deleted.
`idVerificationStatus` remains tracked and surfaced as a **badge** (dashboard checklist,
Identity section, status chip) — it simply never blocks signing or sealing. This is a
truth-restoring change, not a new deviation: it brings the code back to §0.

**Do not reintroduce the gate to "match spec §3".** §0 outranks the spec and was a
deliberate launch decision. Guarded by `wills.service.spec.ts` — the seal/sign tests run
with an `UNVERIFIED` owner and assert `user.findUnique` is never consulted on that path,
so re-adding the gate fails the suite. If v2 ever makes verification mandatory, that is a
new decision with its own section, not a silent restoration of the spec default.

---

## 18. Will step-up re-auth falls back to email when there is no phone (owner, 17 Jul 2026)

Unpublishing or deleting a sealed will requires step-up re-authentication (spec §3). The
code implemented only the SMS half: `verifyStepUp` demanded an SMS OTP and, when the owner
had no phone, threw *"…your account has no phone number. Add one in your profile first."*
There is no such profile screen or route — phone is optional at registration
(`register.dto.ts`, `@IsOptional()`), never collected on the OAuth path, and no endpoint
writes it after signup. So a phoneless owner — the common case (322/324 local users) —
could seal a will and then **never** unpublish or delete it. A dead-end on the owner's own
irreversible actions, over a field they were never required to have.

**Decision: step-up falls back to the account's verified email when there is no phone.**
`WillsService.stepUpChannel` resolves one destination — the phone (SMS) if present, else
the email — and both `requestStepUpOtp` and `verifyStepUp` go through it, so issue and
verify always key off the same `(destination, purpose)` pair. `OtpService.issue` gains an
`'email'` channel. The response carries `via: 'sms' | 'email'` so the client can label the
code prompt correctly.

**Security posture (this is a re-auth on a destructive, legally-meaningful action, so it
is stated deliberately).** Step-up defends against a hijacked *session* by demanding a
second factor the session alone doesn't grant. SMS to the on-file phone is the strongest
and stays the default. Email is a genuine second factor — it proves control of the
account's unique, verified email — and it is **strictly better than the two alternatives
it replaces**: the prior dead-end (no path at all) and forcing every phoneless user to add
a phone. It also honours spec §3's own wording, "SMS OTP, **or** Face ID on mobile": the
spec always contemplated a non-SMS factor; email is the server-side one. This is a
truth-restoring, no-one-blocked change in the spirit of §0/§16 (do not hard-gate the
owner's own actions on an optional field). If a stronger posture is later wanted
(e.g. require re-verifying the email within N minutes, or a mandatory phone for high-tier
wills), that is a new decision.

Covered by `wills.service.spec.ts` (SMS-with-phone vs email-without, and an end-to-end
delete for a phoneless owner) and `otp.service.spec.ts` (channel routing). The step-up +
unpublish/delete flow had **no tests at all** before this.

**Known follow-up (client copy, not behaviour):** the Flutter step-up prompt still says
"SMS". The backend now returns `via`, so the client can say "we emailed your code" when
`via === 'email'`; updating that copy is a UI task, tracked separately. Until then a
phoneless user still receives a working code — by email — just labelled "SMS".

---

## 19. The vault reaches the trustee by recovery code, and only the trustee (owner, 19 Jul 2026)

The DV2.1 prototype's heir view promises *"Vault items assigned to you are available in
your Wasiati account"* (`heirVaultNote`). That promise could not be kept. A `VaultItem`'s
`dataKey` is wrapped with a KEK derived from the owner's passphrase
(PBKDF2-HMAC-SHA256, 210 000 iterations, per-user salt) and **the server holds no
passphrase, no KEK and no plaintext** — `schema.prisma` says so and the vault screen tells
the user *"If you lose your passphrase and Face ID, this vault cannot be recovered — not
even by us. That is the point."* Releasing the vault to heirs was therefore not a feature
that had been left unbuilt; it was cryptographically impossible as designed.

**Decision: the vault goes to the TRUSTEE only, unlocked by a recovery code the owner hands
over while alive. Not to heirs, and not via any key the server can use.**

Narrowing from "heirs" to "the trustee" is the security win, not a compromise: one key to
protect instead of five, given to the single person the owner already chose to execute
their will. Heirs receive the will, the personal message, the estate division and the video
— everything that is not end-to-end encrypted.

### Why this is cheap

Vault encryption is already an envelope: each item has its **own** random 256-bit `dataKey`,
and `encryptedDataKey` is that dataKey wrapped with the owner's KEK. A second recipient is
therefore just a second wrapping of the same dataKey — **the item ciphertext is never
touched and never re-encrypted.**

### Shape

At seal time, on the owner's device (the only place the passphrase exists):

1. Generate a random 256-bit **trustee master key** (TMK).
2. For each vault item, unwrap `dataKey` with the owner KEK and re-wrap it with the TMK.
3. Generate a high-entropy, human-transcribable **recovery code**; derive
   `recoveryKEK = PBKDF2(code, freshSalt, 210k)`; store `TMK` wrapped with it.
4. Also store the TMK wrapped with the **owner's** KEK. This is not redundancy — without
   it, vault items added after sealing could never be wrapped to the trustee, because the
   device would have no way to recover the TMK on a later visit. The owner already holds
   the passphrase, so this grants nothing new.
5. Show the recovery code **once**. The server never receives it.

After release, the trustee enters the code in the portal: derive `recoveryKEK` → unwrap TMK
→ unwrap each `dataKey` → decrypt. All client-side. The server's role is unchanged: it
stores opaque wrapped blobs and still cannot decrypt anything.

Wrapping the TMK with a code-derived KEK — rather than deriving the TMK *from* the code —
keeps the code's (necessarily limited) entropy protecting exactly one small blob, and makes
rotating the code a single re-wrap instead of touching every item.

### The disclaimer, and why its wording matters

This is the one place in the product where a user can permanently destroy something by
losing a piece of paper, so the copy must be blunt about the loss **and** precise about its
bounds. Shown to the owner when the code is generated, and again to the trustee in the
portal:

> **Only your trustee can open your vault, and only with this code.**
> We never see this code and cannot recover it — that is what keeps your vault private,
> and it is why we cannot help if it is lost.
> Give it to your trustee now, and tell them to keep it somewhere they will still have in
> twenty years.
> **If the code is lost, the vault cannot be opened by anyone, ever.** Your will, your
> words for your family and your video message are not affected — those reach your heirs
> regardless.

The final sentence is load-bearing. Without it a reader reasonably concludes that losing
the code loses *the will* — the opposite of true, and a reason to abandon the flow in
alarm. The bound is what makes the warning survivable.

### Consequences accepted

- A lost code is unrecoverable. This is the cost of "not even us", chosen with eyes open.
- The trustee must hold a secret for possibly decades, with no reminder from us.
- Existing vaults need a one-time re-wrap the next time the owner unlocks; until then those
  items have no trustee copy and must not be advertised as recoverable.
- `heirVaultNote` must NOT be ported to the heir view as written. Heirs do not receive
  vault items, and this is the most emotionally loaded screen in the product — it must not
  promise something that will not arrive.

## 20. The madhhab picker stays at TWO schools (owner, 22 Jul 2026)

**Supersedes the "five-school picker" clause of §13.**

§13 records a five-school picker (Jumhūr default, then Ḥanafī / Mālikī / Shāfiʿī / Ḥanbalī).
The owner has since settled the opposite, twice. First conditionally — *"we discussed this
multiple time deep search all scholars if the dif. is only in two keep two"* — and then
flatly, on 22 Jul 2026: *"I THOUGHT WE ALREADY TABLE THIS THAT WE STICK TO THE POPULAR TWO
OPTINIONS?"*

**Decision: the picker ships TWO options — Jumhūr (majority) and Ḥanafī.** That is what the
code already does, so this changes no behaviour. What it changes is the record.

Why this entry exists at all: §13 disagreed with the shipped code AND with the owner, and
`docs/DECISIONS.md` is the top of the source-of-truth precedence chain. So every fresh reader
— human or agent — reached §13, saw a "five-school picker" that was neither built nor wanted,
and re-opened a question the owner considered closed. It was raised at least twice on 21–22
Jul alone. A stale decision doc does not sit inert; it actively regenerates settled work.

The five-school l10n strings exist and are code-generated but no widget references them.
Leave them: they cost nothing and removing them is a separate clean-up call (see the clutter
review). **Do not wire them.**

Untouched by this: the OTHER §13 fara'id clauses (classical radd with Mālikī/Shāfiʿī surplus
to bayt al-māl, dhawu al-arḥām under Ḥanafī, and daughters not blocking uncles/cousins from
the residue) remain open and still require the owner's sign-off ONE AT A TIME, because each
changes computed shares. Two of them are moot in a two-school build — classical radd and the
Mālikī/Shāfiʿī bayt al-māl line only bite under schools that are no longer selectable — so
what actually remains live is the daughters/residue question, which applies under Jumhūr.

### §20 addendum — the measurement behind "two schools" (22 Jul 2026)

The owner's condition was: keep two IF two cover every distinct calculation, otherwise add
the rest — *"If there's a case that we need to have more schools to cover all possibility of
calculations, then do it."* So it was measured rather than assumed.

Across 25 heir configurations run through all five schools, **4 differ, and all four are the
same scenario: grandfather with siblings.** The split is always identical:

| group | behaviour |
|---|---|
| **Ḥanafī** | the grandfather BLOCKS siblings entirely |
| **Jumhūr = Mālikī = Shāfiʿī = Ḥanbalī** | siblings share the residue with the grandfather |

Mālikī, Shāfiʿī and Ḥanbalī are identical to Jumhūr in every other case. Adding them to the
picker would give the owner three extra labels that compute exactly what "Jumhūr" already
computes — the appearance of choice with no arithmetic behind it. **Two options are complete.**

**The load-bearing assumption, and the one thing that would change the answer:** this holds
under CONTEMPORARY radd, where surplus returns to the heirs under every school
(`RADD_SCHOOLS` in sharia-calculator.ts). Classical Mālikī/Shāfiʿī doctrine sends that surplus
to bayt al-māl, which would split them into a THIRD group and make two options incomplete.
§13's "classical radd" clause therefore conflicts with its own five-school clause only in
appearance — but it does conflict with §0, which chose contemporary radd. **§0's contemporary
radd stands**, because it is what ships, what the engine implements, and what makes a
two-option picker correct.

Consequence to be aware of: the `BAYT_AL_MAL` branch in the engine is currently unreachable,
since every school is in `RADD_SCHOOLS`. It is left in place deliberately — it is the
implementation of the classical position, ready if that decision is ever revisited.

This is pinned executably in `sharia-calculator.spec.ts` ("school coverage — two options are
complete", 14 tests). If `RADD_SCHOOLS` ever narrows, those tests fail — and that failure is
the signal to revisit the school COUNT, not to edit the test.

## 21. Contemporary radd is final; the picker ships two schools, honestly labelled (architectural ruling, 22 Jul 2026)

The owner's requirement was unambiguous: *"Whatever school of thought is selected that
calculation needs to reflect"*, and *"there's no room for error on the calculation"*. Measured
against that, the engine failed: it exposed five madhhab values, and MĀLIKĪ, SHĀFIʿĪ and
ḤANBALĪ were **byte-identical to JUMHUR across 18,216 heir configurations**. Three of the five
were decoration.

The fix was not to add three more computations. It was to decide which doctrine ships.

**Ruling 1 — CONTEMPORARY radd, final.** Classical Mālikī/Shāfiʿī send a surplus to bayt
al-māl rather than returning it to the sharers. That presupposes a functioning treasury. In
the jurisdictions this product actually serves, a bequest to a non-existent recipient
**lapses** — the surplus falls to intestacy and a secular court divides it. That is the worst
outcome a Sharia-compliance product can print, and it is why contemporary Mālikī/Shāfiʿī
practice (Egypt's statute, Malaysian practice) applies radd. This confirms §0; it does not
reopen it.

Geo-switching was rejected outright: **madhhab is personal, not territorial.** A Shāfiʿī in
Toronto has no "country rule", and asking a grieving family to understand fiqh history to pick
correctly is not a product. One computation per school selection, worldwide.

**Ruling 2 — two options, and the LABEL carries the truth.** "Decoration is unacceptable" and
"a selected school must compute that school" are only in tension if the label lies. They now
read:

- *"Jumhūr — the majority position as applied today, followed by Mālikī, Shāfiʿī and Ḥanbalī
  communities"*
- *"Ḥanafī — differs where a grandfather inherits alongside siblings"*

A Shāfiʿī user's selection is therefore honest rather than absent. The five values stay in the
engine's `Madhhab` type (tested, fingerprinted, backward-compatible); the picker and the draft
DTO accept two.

**Ruling 3 — escheat is NOT responsibly implementable, and the branch stays dead.** A will
line naming "bayt al-māl" names no legal person. The only responsible future form is a
testator-named charitable/waqf fallback, which is scholar-gated and not now. `BAYT_AL_MAL`
remains intentional dead code; the specs fail if `RADD_SCHOOLS` narrows, which is the correct
tripwire.

**Guarded by:** `sharia-engine-fingerprint.spec.ts` (all five schools hashed over 3,586
configurations; mutation-proven to isolate a single-school change) and the alias tests in
`sharia-calculator.spec.ts` which state the aliasing as INTENT, so it can never again be an
accident nobody noticed.

**Open, and needing a QUALIFIED SCHOLAR rather than an engineer:**

1. **Al-mushtaraka** (husband + mother + uterine siblings + full brothers) is the one live
   crack in the label. The engine currently excludes the full brothers — the Ḥanafī/Ḥanbalī
   answer — under *every* school, so "followed by Mālikī, Shāfiʿī" is contestable for exactly
   that family shape. The classical schools split 2–2 here. If a scholar rules for tashrīk
   under Jumhūr, that **changes JUMHUR output**, and needs its own entry, a fingerprint
   re-baseline, and a check that no sealed will carries that configuration.
2. The daughters/residue question already flagged in §20.
3. The label wording itself — "the majority position as applied today" is a fatwa-adjacent
   claim printed into a sealed legal document.

**Shipping verdict:** shipping the current two-school arithmetic is acceptable — it matches
widely published contemporary references, and it is mutation-proven and fingerprint-guarded.
What is NOT acceptable is claiming scholarly certification before a scholar has reviewed the
engine. So the document and UI carry a plain line that shares are computed per the selected
school's contemporary application and the testator may consult a scholar of their own school;
the review is commissioned in parallel and the hedge is removed when sign-off lands. **The
scholar review is a launch-marketing gate, not a launch gate.**

---

## 22. The guardianship note asserts no order (owner-delegated, 22 Jul 2026)

**Deviates from the DV2.1 prototype copy** (`Wasiati Prototype.dc.html`, `gIslamicNote`, both
languages). Precedence source #3 is overridden here deliberately; do not "restore" it.

**What was there.** Create-will step 3, the gold note under *Islamic order of guardianship*:

> *"Guardianship follows the sharia order — the father, then the paternal grandfather, then
> male relatives of the father's line — as determined at the time."*
> «تتبع الولاية الترتيب الشرعي — الأب ثم الجد لأب ثم عصبة الأب — بحسب الحال عند التنفيذ»

**Why it is wrong.** `docs/FIQH_REVIEW.md` §9 has the sourcing and the per-school table. In
short: that chain is neither custody nor property guardianship. **Ḥaḍāna begins with the
MOTHER in all four Sunni schools** — in none does it start with the father — and **general
ʿaṣaba (brothers, uncles) take no automatic wilāya over a minor's property in any school**;
in default the authority is the **qāḍī / court**. The sentence appears to import the Ḥanafī
*wilāya ʿalā al-nafs* / marriage-guardianship order and present it as the agreed sharia order.
Ḥanbalī and Mālikī give the paternal grandfather no automatic role at all, so no single
sentence can state "the" order truthfully — and our picker's **Jumhūr** option aliases three
schools that diverge on exactly this point, so it could not be stated per-selection either.

**Decision: the note states no order.** It now reads:

> *"This option names no one. It directs that your children's care, and guardianship of their
> share, be settled under the sharia rules and the competent court applying at the time — the
> schools differ, and the two need not fall to the same person. To choose the person yourself,
> which every school allows, use "Name a guardian"."*
> «لا يعيّن هذا الخيار شخصاً بعينه، بل يوجّه بأن تُحدَّد رعاية أولادك والولاية على أنصبتهم وفق
> الأحكام الشرعية والمحكمة المختصة عند التنفيذ — وتختلف المذاهب في ذلك، وقد لا يجتمع الأمران في
> شخص واحد. ولاختيار الشخص بنفسك، وهو ما تجيزه المذاهب كلها، اختر «تسمية وصيّ».»

Three things are deliberate in it. It **names no order**, matching what the sealed document
already does (`will-document.service.ts`, pinned by a test — that non-assertion is not
reopened here). It **separates care from guardianship of the share** without the terms
ḥaḍāna/wilāya, which carries §9's central distinction in plain language and stops a testator
reading this mode as displacing the mother. And it **points at `named`**, which rests on the
one point agreed across all four schools — the father's power to appoint a waṣī by will — and
is the only mode a US or Canadian probate court can give effect to.

**How this was decided.** Four candidate wordings and three scope options were put to the
owner on 22 Jul 2026; the owner delegated the choice — *"Do what's best"* — rather than
picking one. **This is therefore an engineering ruling made under owner delegation, not the
owner's own words on the fiqh**, and it is recorded that way on purpose. It is safe in that
direction: it removes a claim rather than adding one. A future ruling that wants to *state* an
order needs a qualified scholar and its own entry.

**Scope: the note only.** `cwGIslamicLbl` ("Islamic order of guardianship") and `cwGuardSub`
("Who cares for your children under 18…") still use *order* framing and still describe the
card as being about care alone. That is a smaller inaccuracy than the one fixed here and it is
left standing rather than rewritten unilaterally — **still open, see §9 open questions 1–5.**

**Applied to:** `app_en.arb` + `app_ar.arb` (`cwGIslamicNote`) and the three generated
`app_localizations*.dart` files via `flutter gen-l10n`. The admin Content tab can override it
at runtime per §4. No test pinned the old string; nothing else changed.

## 22. Text colours — "Ironclad" tier (owner, 23 Jul 2026)

The owner reported the gold accent and the grey note/caption text as unreadable in both
themes — "vision impaired people can't read that" — and, across several mockup rounds,
rejected every readable-but-subtle pass as still too faint. Decision: **maximum legibility
over subtle hierarchy.** The neutral tiers are pushed close to the primary ink (muted ~9:1,
faint ~7.5:1 on the card surfaces #F5EFE1 / #253029) and told apart by weight and size, not
by fading. The dark greys also drop their old bottle-green tint, which read as murk. The
gold ink becomes a deep antique amber-bronze (#714F14 light / #D6AD5B dark, ~6.5:1), never
the yellow that an earlier brighter pass was rejected for; it double-duties as the gold CTA
field, which only improves (a darker field raises its onDark label's contrast).

## 23. "Multiple wills · linked accounts" is not sold (owner, 24 Jul 2026)

`WASIATI_SPEC.md` §2 lists "multiple wills · linked accounts" among Premium's capabilities,
and the Premium pricing card sold it. **Nothing implements it.** Will limits are
tier-INDEPENDENT: `MAX_UNSEALED_WILLS = 3` and exactly ONE sealed will, enforced for every
tier alike in `wills.service.ts` (at create, sign, seal and revise). There is no
linked-account, seat or family-member concept anywhere in the codebase. A Premium buyer
receives no more wills than a Standard one.

**Decision: take the claim off the card rather than build the feature now.** Selling a
capability the buyer does not receive is a complaint — and a refund — waiting to happen, and
building real multi-will support first needs product answers this catalogue change does not:
which will is released to heirs at death, whether a second sealed will supersedes or
coexists with the first, and how witnesses and trustees map across them.

**Applied to:** `PREMIUM_FEATURES` in `prisma/seed-pricing.ts` (with a comment naming this
section) and the nine live `PricingPlan` rows that carried the bullet. Restore the bullet in
the same commit that builds the feature — not before. Until then this section overrides spec
§2's capability table on this one line.

## 24. Ameen runs on Gemini, behind a provider port (owner, 24 Jul 2026)

Ameen was wired directly to the Anthropic Messages API. **Decision: move it to Google
Gemini** — the owner's call, on cost: this feature's per-session volume made the Claude
API too expensive for the price points in §13. Nothing about the product changes; the
model behind the conversation does.

**The integration now has a port, which it never had.** `AiProviderPort` + the
`AI_PROVIDER` token mirror `PaymentProviderPort` / `IdentityProviderPort` /
`StorageProviderPort`, with `GeminiAiProvider` and `UnconfiguredAiProvider` behind it.
AI was the one outbound integration that skipped the repo's own convention, and the
cost of that showed up immediately: the provider's URL, auth headers, request body,
response shape **and its wire format in the database** were all spread through
`AiIntakeService`. The next swap is an adapter.

**The stored transcript is now provider-neutral** — `{role, content: "plain text"}`
instead of the provider's content-block array. Two things follow. The app needed no
change (its resume view already read a string `content`), and a future provider change
cannot strand old conversations. Existing rows are still read via a tolerant parser;
there was nothing to migrate in practice (29 sessions, 28 empty, none completed — the
key was never obtained, so the feature never ran).

**A latent bug went with it.** The old loop pushed the assistant's `tool_use` block
into the transcript and then sent the next user turn with no matching `tool_result`,
which the Messages API rejects — so the intake would have failed on the *second* turn
of every conversation, surfacing as the generic 503. Turns now carry text only and the
extraction is re-derived each turn (the system prompt already asks for it cumulatively),
which is both simpler and portable. This module had **no tests at all**, which is how
that survived; it now has 21.

**Env:** `GEMINI_API_KEY` (empty ⇒ clean 503 and the app falls back to the guided form),
optional `GEMINI_MODEL` (default `gemini-2.5-flash`, chosen for cost) and
`GEMINI_BASE_URL`. `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` are gone.

**Unchanged:** voice. STT/TTS are on-device in Flutter (`speech_to_text`, `flutter_tts`)
with no vendor key, so "Ameen AI (chat + voice)" keeps its meaning. Also unchanged: the
`finalize()` validation boundary — the model still never writes to a will, it proposes an
extraction that is filtered against `HEIR_RELATIONS` and `AssetType` before anything is
created.

## 25. AWS launch topology, MFA ladder, and the enforced paywall (owner, 28 Jul 2026)

The full plan, research and cost model live in the session plan of 28 Jul 2026; the
decisions and their code consequences are recorded here. Supersedes §0's "all four
regions at once".

**One region at launch: `ca-central-1` (Montreal), serving every market.** The legal
research found NO market requires in-country storage — Saudi PDPL has no localization
mandate (it requires transfer safeguards and applies to Saudi residents' data wherever
servers are), PIPEDA has none, the US has none. Region choice is therefore preference
and law, not cost (it is 0.03% of total cost at scale). Not a US region per the
owner's data-sovereignty preference — recorded honestly: the CLOUD Act keys on
provider nationality, not geography, so no AWS region defeats it; what does is the
client-side-encrypted vault model, which is the direction of travel. Expansion is a
new Terraform `envs/` directory when a market demands its own stack.

**Code: `SERVED_REGIONS`.** `REGION` names the shard; `SERVED_REGIONS` (default: just
`REGION`) lists the markets it accepts signups for. Launch: `US,CA,KSA` on one stack.
Splitting a market out later = remove it from the list, deploy its stack — no code.

**Residency is derived, not asserted.** `register()` derives the user's region from
`countryToRegion(addressCountry)` — the client's `region` field (a build-time
constant that made the old guard compare the deployment to itself) is ignored.
Address country, not nationality, is the key — matching PDPL's own "residing in KSA"
test. KNOWN LIMIT: wrong key for a future EU market, where succession follows
nationality; revisit then.

**The paywall is server-enforced at seal.** Paywall-at-login (§13) was UI routing
only; `seal()` now requires a live paid entitlement of any tier. Drafting stays free;
the binding act is what is sold. Cost tiers in every plan/model mean PAYING customers.

**MFA ladder (supersedes SMS-by-default).** Passkey and OAuth promoted first (both
$0 and already built), TOTP next (to build — `User.mfaSecret` exists unwired), email
OTP as fallback, SMS LAST and on request only — over WhatsApp in KSA
(`sendWhatsapp()` exists; `mfaChannel()` must learn to select it). Rationale: Saudi
SMS is $0.1949/message — 15.6× US — and with SMS-default MFA it is the single
largest cost at scale (~$164k/mo at 1M customers, 3× the entire Stripe line).
Email-OTP-as-default was considered and REJECTED: password reset lands in the same
inbox, so email compromise would be total account compromise. Recovery codes, not
SMS, are the safety net; at least two recovery routes before an account counts as
set up. Step-up OTP stays for seal/unpublish/delete/death-claim.

**Mobile: web + iOS + Android at launch; iOS is a NO-PURCHASE companion.** Payment
stays on the web (Stripe ~4.9%) — selling subscriptions inside the iOS app would
trigger Apple IAP at 15–30%, the largest avoidable cost in the product. Both stores
ship together (one release cycle; both needed the voice-permission fixes).

**Future markets noted:** Indonesia and Pakistan. Language is cheap (~1,300 strings;
RTL already solved). The real work: Indonesia is predominantly Shafiʿī — which
legitimately reopens the two-school picker decision (§20) for that market — and
Stripe does not operate in Pakistan (local PSP behind `PaymentProviderPort`).

**Deploy blockers closed with this decision** (one commit each, 28 Jul 2026): trust
proxy hop count (`req.ip` was the ALB's address — in will signature certificates);
`GET /health`; BullMQ `rediss://` TLS; SMTP vars documented (unset = every email
silently dropped); `PASSKEY_ORIGIN` corrected to app.wasiati.com; Gemini
`thinkingBudget: 0` + empty-turn refusal; cron advisory locks (two tasks would
double-charge renewals); presigned-PUT Content-Length actually signed; iOS speech
permission (OS terminated the app on the Ameen screen) + Android `<queries>`; CI
matrix QA dropped and real API URLs added; Dockerfile schema-engine fetch + `:tools`
stage for migrations/seeds.

## 26. Posthumous erasure is verified before it is claimed (29 Jul 2026)

`purgeUser()` deleted database rows and wrote the "permanently erased" `DataPurgeLog`
tombstone **in one transaction, and never called storage at all**. Every id document,
death certificate and legacy video stayed in the bucket — with its `FileObject` row
cascade-deleted, so nothing knew they existed — while the compliance log, and the notice
sent to the family, said they had been destroyed. The orphan reaper eventually swept
them, but only as a *delete marker*, which on a versioned bucket erases nothing.

**Decision: erase the objects FIRST, verify, and only then delete the rows and write the
tombstone.** The ordering is the safety argument, and it is not interchangeable:
`scheduledPurgeAt` on the user row *is* the retry intent (`runDailyPurge` re-selects by
it nightly). Delete the user first and a crash before the sweep leaves no row to retry,
no tombstone, and stranded bytes findable only by scanning the bucket — a silent,
permanent compliance failure. Erasing first turns every failure into a harmless retry
and makes "a tombstone exists" imply "erasure was verified".

Consequences, all now in code:
- **Version-aware erasure.** AWS: *"a simple DELETE cannot permanently delete an
  object"* — it inserts a delete marker and every prior version stays readable. So
  `deleteAllVersions`/`purgePrefix` list and delete every version **and delete marker**
  by version id. `deleteObject` keeps its old behaviour and its comment was corrected;
  it is not erasure.
- **The verification uses `ListObjectVersions`, never `ListObjectsV2`** — the v2 listing
  hides noncurrent versions and delete markers, so it would report "empty" for a prefix
  whose every byte is recoverable: a check that always passes.
- **Swept by prefix (`<kind>/<userId>/`), not by the recorded keys** — an upload that was
  presigned and PUT but never confirmed has no row and is just as sensitive.
- **`DeleteObjects` per-object errors are read.** S3 returns them inside an HTTP 200 and
  the SDK does not throw; unread, an Object Lock or a missing permission would be
  reported as success.
- **Uploads are refused once `scheduledPurgeAt` is set**, closing the race where a
  presigned PUT lands bytes after the sweep verified the prefix empty.
- **The malware path now erases all versions** (recoverable malware is an anti-goal) and
  logs failures instead of `.catch(() => undefined)`.
- **The orphan reaper deliberately still uses the plain delete.** Versioning is currently
  the only backup, and the reaper — which decides what to delete by diffing storage
  against the database — is exactly the component whose bugs need a recovery net. Its
  leftovers are handled by lifecycle expiry, not by making it destructive.
- No migration: the evidence (method, counts, `verifiedEmptyAt`) rides in the existing
  `recordsDeleted Json?`. `fileObjects` is now counted explicitly rather than cascading
  away uncounted.

**Bucket constraints this creates — must hold at AWS cutover, or the tombstone lies:**
1. **No Object Lock in compliance mode** (and no legal hold) with retention outliving the
   purge window: nothing, not even root, can delete a locked version, so the purge would
   fail per-object forever.
2. **MFA Delete off** — it requires root + an MFA code on every version delete, which a
   cron cannot supply.
3. Lifecycle: `NoncurrentVersionExpiration` (14–30 d) + `ExpiredObjectDeleteMarker` to
   clear the reaper's leftovers.

**Deferred, and REQUIRED BEFORE the DR work in §25 ships:**
- **Cross-region replication breaks this.** Version deletions are never replicated (AWS
  designs it that way to resist malicious deletion) and delete markers are not replicated
  by default — so the day CRR is enabled, a "successful" purge would leave a complete,
  readable copy of every document in the replica region, as current objects with no
  expiry path. The purge must then erase in both buckets (IAM for both) and verify both.
- **Crypto-shredding** (per-user key, destroyed at purge) is the only mechanism that also
  reaches replicas and backups. The vault is already client-encrypted; uploaded documents
  are not. This is the durable answer once replicas or AWS Backup exist.

### 26a. The purge also redacts the KYC vendor's copy (29 Jul 2026)

The government-ID scan and the selfie are the most sensitive artefacts the product ever
handles and they are **not in our bucket** — Stripe holds them, on its own multi-year
schedule. Erasing our storage while leaving those behind made "permanently deleted"
false exactly where it matters most.

`purgeUser` now calls `IdentityProviderPort.redactPersonalData(userId)` before the
transaction, alongside the storage sweep. Stripe sessions are found by
`client_reference_id` (stamped with our user id at creation) — the only server-side
filter Stripe's list endpoint offers, since metadata is explicitly not filterable, and
the session id is not persisted on our side.

Two honest limits, both recorded in the tombstone rather than papered over:
- **Redaction is asynchronous** — Stripe documents up to **four days**, completing with
  an `identity.verification_session.redacted` event. So unlike the storage sweep, what is
  verified here is that the REQUEST was accepted; `completesWithinDays` records the
  vendor's own bound. Gating the tombstone on the completion webhook would stall every
  purge for days, and the identity webhook cannot be trusted until the shared-secret
  split (§26 constraints) ships.
- **Sumsub has no redaction implementation** and an unconfigured adapter cannot reach any
  vendor. Either reports `supported: false`, and the purge REFUSES to proceed for a user
  who verified on the document rail — the documents would outlive the purge, so the
  tombstone must not be written.

Follow-up worth doing: an ID scan is collected for a one-time identity check and should
not inherit the will's retention at all. Redacting shortly after a verification completes
— rather than only at death — would remove the artefact from the vendor years earlier.

## 27. Legal hold — the purge can be stopped (29 Jul 2026)

The posthumous purge is an automated, irreversible destruction job aimed at the one
document a family may end up in court over, and **nothing could stop it**. A contested
will, a probate dispute or any preservation obligation is an ordinary event in this
domain; the product would have destroyed the disputed instrument on schedule and written
a tombstone recording that it meant to. That is the shape of spoliation FRCP 37(e)
exists for, and it is the kind of exposure no amount of privacy engineering offsets.

`User.legalHoldAt` (+ `legalHoldReason`, `legalHoldBy`) suspends the purge indefinitely,
outranking `scheduledPurgeAt`. Additive, nullable migration; existing rows are unheld.

- The nightly sweep **excludes** held estates, so a hold is not retried and error-logged
  every night for years.
- `purgeUser` checks it **again**, because the admin "purge this account now" endpoint
  bypasses the nightly query entirely — a one-click irreversible destruction of preserved
  evidence is exactly what must not be reachable.
- The check runs **before** the storage sweep and the KYC redaction. A refusal that has
  already wiped the bucket is not a refusal; this is the same ordering rule as §26.
- Placing a hold **requires a written reason** (the audit trail has to answer "why was
  this estate preserved for three years?"), and releasing one logs loudly, because it
  re-arms an irreversible job.

Still open, and owner/counsel decisions rather than code (from the 29 Jul best-practice
benchmark): splitting the retention clock so the testamentary instrument survives on a
years-scale schedule rather than the 90-day personal-data clock; demanding the RUFADAA
documentary set (letters of appointment / court order, not a death certificate alone) at
claim intake; and California's 30-day court-lodging duty.

## 28. Crypto-shredding: SSE-C rejected, scope cut to Postgres, backups come first (29 Jul 2026)

Investigated per-user crypto-shredding so that erasure would reach future replicas and
backups (§26 defers exactly this). The proposed mechanism — one CMK, a per-user wrapped
DEK, and **SSE-C** so S3 encrypts objects under that DEK — was researched and adversarially
reviewed, and is **rejected**. Four independent reasons, each sufficient:

1. **The key cannot be injected server-side.** For a presigned URL only
   `x-amz-server-side-encryption-customer-algorithm` is signed; the client must send the
   raw key and its MD5 as real headers. So the DEK must travel to the browser — the very
   thing the design chose SSE-C to avoid.
2. **It would hand the whole-estate key to an unapproved stranger.**
   `claim-uploads.controller.ts` presigns a death-certificate upload attributed to the
   DECEASED owner for a CLAIM_SUBMIT token holder — no account, pre-review, possibly
   filing against a living person. That presign would have to carry the deceased's DEK,
   the single key over their government ID, videos and every encrypted column.
3. **AWS is retiring it.** Since April 2026 new general-purpose buckets block SSE-C by
   default (403 unless deliberately re-enabled), and **AWS Backup cannot back up SSE-C
   objects at all** — so "future backups become inert" is really "managed DR becomes
   impossible" for a wills product.
4. **It breaks the bare-URL contract.** `presignDownload` is consumed as a self-contained
   capability — heirs' inline video playback, the claim certificate link. A GET without
   the key headers is rejected, so `<video>`, native players and `<a href>` all stop
   working; the fallbacks are OOM-prone Blob downloads or proxying bytes through the API,
   abandoning the direct-to-S3 architecture.

Also established: **destroying a wrapped-DEK row is not erasure at T+0.** Postgres MVCC
leaves the old tuple until VACUUM, WAL and archives retain it, and it sits in every base
backup; an UPDATE-to-overwrite writes a NEW tuple and leaves the old bytes. And a shared
CMK can never be scheduled for deletion without shredding every user, so backup expiry —
not key destruction — is the real erasure date for anything already backed up.

**Revised plan.**
- **S3: change nothing in the data path.** Use SSE-KMS with a bucket key (invisible to
  presigned URLs, zero client changes) for at-rest compliance. Per-user erasure stays the
  existing verified version-aware deletion, which reaches every byte that exists today.
- **Replicas, when they exist: sweep them directly.** A config list of replica buckets and
  a loop over the erasure already built — far simpler and more provable than crypto, and
  it moots the "version deletes do not replicate" problem by deleting in each bucket.
- **Postgres column encryption** (per-user DEK, server-side only, HKDF-derived) is where
  the residue argument genuinely bites and where the server already does crypto in-band.
  Its real cost is not the crypto: `portal.resolveParty`, `deathClaims.resolveDeceased`
  and `recipientsForUser` match roster **email/phone in SQL**, so those columns need
  blind-index (HMAC) columns and every such query rewritten — that is the bulk of the work,
  and getting it wrong silently breaks the death path.
- **If S3 crypto-shred is ever demanded**, do client-side AES-GCM with server-issued
  **per-object HKDF subkeys** — never the master key, never SSE-C.

**Priority inversion, recorded because it matters more than any of the above:** this
product has **no Postgres backups at all** — single region, S3 versioning as the only file
safety net. Losing a sealed will is a worse failure than 91st-day residue in a WAL segment.
PITR backups with a deliberate retention number and a *tested restore* come before any
shredding work, and the key-table retention policy should be chosen at the same time so
"erasure completes at purge + retention" is a designed number rather than an accident.

## 29. The will reads as narrative by default (owner, 5 Aug 2026)

DV2.1's will document has always had two estate formats — the table and the
auto-written narrative ("I declare that, as of the sealing of this will, I own the
following assets…" / «أُقرّ بأنني أملك عند ختم هذه الوصية الأصول الآتية…») — and both
were fully built, server and app. But every surface defaulted to the table, so the
first document anyone read sounded like an inventory printout, and the narrative sat
behind a toggle most people would never touch.

The owner's ruling, testing the built app: the narrative is the better language in
both English and Arabic, and it should be what a person gets without asking. A will
should sound like a will.

Defaults flipped, table retained one tap/param away:
- `willPreviewChoiceProvider` (the preview page's ESTATE FORMAT toggle) → `essay`
- the export sheet (`will_pdf.dart`) → Narrative preselected and listed first
- `PortalApi.pdf` (the heirs' copy — the audience this register exists for) → `essay`
- both server controllers' fallback when no `format` is passed → `essay`

The prototype's own default was `table`; this deviates from it deliberately, on the
owner's direct instruction, which is the precedence rule of this file.
