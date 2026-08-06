# Flutter framework review — findings & status

A 4-dimension audit (theming, widget-composition, layout/RTL, state) found 33
framework/idiom issues. Applied fixes below; remaining are lower-priority follow-ups.

## Fixed
- ✅ **Theme default font** — `ThemeData.fontFamily = Public Sans` (no accidental Roboto).
- ✅ **Design-system colors** — `welcome_screen` uses `WasiatiColors` (was 17 hardcoded hexes).
- ✅ **Const-correctness** — enabled `prefer_const_*`, `use_build_context_synchronously`,
  `use_key_in_widget_constructors`; `dart fix --apply` (20 fixes / 15 files).
- ✅ **State crash bugs** — `mounted` guards added: `video_record` (camera enum + start/stop),
  `kyc` (`ref.invalidate` after `launchUrl`).
- ✅ **RTL** — ai-intake chat bubbles use `BorderRadiusDirectional` (tail mirrors in Arabic).
- ✅ **WasiatiCard** — one design-system card replaces 9 duplicated `_Card` classes (tokens,
  r18, dark-aware); zero visual change, verified by render.
- ✅ **Brand logo** — signed-W seal moved to the design system as `WasiatiSeal`; `WasiatiLogo`
  wired to it (was an "interim" mark); `welcome_screen` consumes it.
- ✅ **WasiatiUpgradePrompt** — shared 403 paywall card (+ `isPaywall()` helper) for vault/burial.
- ✅ **Tokens** — `auth_scaffold` and `verify_mfa` use `context.tokens` instead of manual
  brightness branching.

- ✅ **welcome dark-mode** — landing is now theme-aware (bg/cards/headings/body/hairlines from
  Theme + `context.tokens`; brand green band + gold + on-green text stay fixed). Verified in
  light *and* dark via render.
- ✅ **Dialog controller leaks** — disposed in `vault._addItem`, `will_detail` bequest +
  witness/trustee, `assets._add`.

## Remaining follow-ups (medium/low)
- ⬜ **More dedup** — `_OfferBanner` (dashboard/pricing), segmented tab (`_periodTab` /
  `_BillingToggle`), stat tile (`_StatCard` / `_stat`) → promote to `WasiatiOfferBanner` /
  `WasiatiSegmentedControl` / `WasiatiStatTile`.
- ⬜ **welcome text roles** — derive header/hero/title styles from `textTheme` roles.
- ⬜ **admin_console dialogs** — `_editPrice`, `_newPromo` controllers not disposed (admin-only).
- ⬜ **Minor tokens** — dark `shadow` uses pure black; nafath badge uses `goldSoft` vs `tokens.gold`.
- ⬜ **Rail SafeArea** — `SafeArea(right:false)` should flip with `Directionality` in RTL.
- ⬜ **Theme switch knob** — uses physical `Alignment.centerLeft/Right` (doesn't mirror in RTL).
