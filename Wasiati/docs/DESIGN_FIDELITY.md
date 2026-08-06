# Design fidelity punch-list (vs prototype + DESIGN_TOKENS)

Compiled from a 4-way screen audit against the design package — now located at
`C:\Users\raed1\Downloads\RA Business\Wasiati.com DV2.1\Exports\wasiati-dev-handoff\Wasiati Prototype.dc.html`
and `WASIATI_HANDOFF.md` there (the DV2.1 package of record; the older
`Downloads\Wasiati Ship Package\` path no longer exists — see repo `CLAUDE.md` for
source-of-truth precedence). Already shipped: **bundled fonts**
(Fraunces / Public Sans / Almarai / Amiri, off runtime google_fonts) and the **designed
230px bottle-green nav rail**. Those were the dominant "doesn't look like the design"
causes. Remaining items below, by screen.

Legend: ✅ done · ⬜ todo · 〜 minor/optional

## Auth & landing
- ✅ **sealed_screen** — sacred Arabic was "الله بارك"; corrected to **"اللهم بارك"** (Allāhumma
  bārik), placed large above the title; added the third "Back to home" action.
- ⬜ **login** — lead with sign-in METHODS (Google/Apple → Passkey → Nafath[KSA, RECOMMENDED] →
  "Continue with email" revealed on tap), region-detected note; title "Welcome to Wasiati".
  Currently email-first with methods greyed as "coming soon".
- ⬜ **welcome/landing** — missing the **Quran 2:180 band** + **Bukhari/Muslim hadith band**
  (signature). Hero "Don't let two nights pass without a will!".
- ⬜ **verify_mfa** — single field → **6 gold-focus cells** + **resend countdown**; copy
  "Enter the 6-digit code" / SMS-to-number subtitle.
- ✅ **register** — removed the region dropdown (region comes from IP, per spec §5).
- ⬜ **settings** — add **Face ID (open app)** + **Face ID (vault)** toggles; Dark-mode +
  Match-system switches.
- ✅ **dashboard** — added "✓ Identity verified" chip; dropped the flag emoji on the region chip.

## Plans / Vault
- ✅/⬜ **pricing** — MOST POPULAR badge now has **no star, pinned to the START edge**, and is
  **data-driven** (sits on the actually-most-subscribed tier); the 3-segment billing toggle,
  promo card, and paired Manage-billing pill all ship. Still todo: a **referral card** on the
  pricing page (referrals live on their own screen today).
- ⬜ **vault** — unlock "forgot passphrase" callout → **1.5px gold + outline seal**; header →
  live **auto-lock countdown**; secret reveal → **10s reveal timer** + auto-hide footnote;
  secret-card layout (emoji tile + monospace value + gold reveal); copy "Vault is locked".
- 〜 **kyc** — no prototype counterpart; structurally sound. (Align PENDING color with admin
  amber, optional.)

## Will flow
- ✅ **create_will** — Step 1 heirs now use **structured counters** (Male/Female, spouse/wives
  stepper or husband toggle, sons/daughters steppers, parent toggles, folded extended family);
  the live fara'id donut recomputes on every tap. (Still todo: donut CENTER showing **bequest %**
  with slices scaled to 100−bequest; segmented step-progress bar; the **dashed gated** AI-pill
  variant for Standard — the solid AI pill ships.)
- ✅/⬜ **will_detail** — **Basis column now shows the real fiqh basis** (Qur'an/Sunnah citation,
  EN+AR, not the relation). Still todo: table header on **#E2D6BC fill, uppercase 11/700**;
  combine into one **"WITNESSES & TRUSTEE"** card; "ID MATCHED" pill + witness note; titles.
- ✅ **wills_list** — single-column **horizontal rows** (seal + info + "Open ›") shipped, not a
  2-col grid; tappable rows via WasiatiCard onTap.
- 〜 **review_seal** — bespoke; reasonable. Prototype folds review into create step 4.
- 〜 **focus mode** — rail should collapse to 64px during create/review (cross-cutting).

## Admin / other
- ⬜ **admin_users** — data table: header **#E2D6BC uppercase 11/700**, **zebra rows**, ID as
  **semantic status dot+label**; add Signups(30d) / KPI cards / Export.
- ✅ **death_claims_admin** — reject via **inline danger panel, Confirm disabled until reason**
  and status **dots** shipped. (Still todo: the Release "separate, logged action" note.)
- ⬜ **burial** — prominent success **"Zero interest · zero profit"** line; "CUMULATIVE PROGRESS"
  heading; "TODAY'S PRICE" eyebrow; title "Burial pre-planning". ⚠ Do NOT follow the
  prototype's "installment(s)" wording — `docs/DECISIONS.md` §6 mandates **"contributions"**
  (US/CA consumer-credit law). Shipping copy already uses "contributions"; only match the rest.
- 〜 **zakat / legacy / assets / admin_content** — match well; only minor copy/token nits
  (legacy video badge tier; content key as monospace chip).
