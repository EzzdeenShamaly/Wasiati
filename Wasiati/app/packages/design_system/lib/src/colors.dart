import 'package:flutter/widgets.dart';

/// Wasiati brand palette — from the approved Claude Design handoff.
///
/// Direction: parchment + soft bottle green carry the dominant visual weight;
/// brass/gold is a genuine warm highlight (not a sparing trim); ink navy is
/// reserved for typography and fine accents only, never a large background field;
/// black is avoided entirely as a UI color, in both light and dark.
abstract final class WasiatiColors {
  // --- Light ("Parchment") -------------------------------------------------
  // Core brand
  static const parchment = Color(0xFFECE3D0); // app background
  static const bottleGreen = Color(0xFF2F4A3D); // primary buttons, nav rail, brand
  static const brassGold = Color(0xFFA87B33); // highlight: focus rings, badges, active accents
  static const inkNavy = Color(0xFF1C2333); // typography + fine accents only

  // Parchment tints/shades (surfaces)
  static const parchmentLight = Color(0xFFF5EFE1); // cards / raised surfaces
  static const parchmentDeep = Color(0xFFEDE6D4); // sunken fills, borders, zebra rows
  static const desk = Color(0xFFE3D8BF); // desk backdrop behind the app frame

  // Green scale
  static const greenDeep = Color(0xFF223529); // pressed / dark green surface
  static const greenSoft = Color(0xFF4A6B5A); // hover / secondary green
  static const greenTint = Color(0xFFEBEFE7); // chips, subtle fills

  // Gold scale
  static const goldSoft = Color(0xFFC89A4E);

  /// Light-theme gold ink — and the light-theme field of the gold CTA
  /// (`WasiatiButtons.goldSolid`), which carries `onDark` on it where raw [brassGold]
  /// managed only 3.22:1 (DECISIONS §15). Two jobs, one hex: re-tune it as type and the
  /// CTA moves too. theme_contrast_test pins both.
  ///
  /// The "Ironclad" value (owner pick, DECISIONS §22): a deep antique amber-bronze at
  /// 6.5:1 as type on the card surfaces — the owner found earlier golds unreadable and
  /// wanted maximum clarity, not a decorative accent. The CTA's other job only improves:
  /// a darker field raises the ratio of the onDark label sitting on it.
  static const goldDeep = Color(0xFF714F14);

  /// [goldDeep]'s dark-theme counterpart, theme-swapped so gold type inverts along the
  /// scale instead of staying dark on a dark card. Read it through `context.tokens.goldInk`,
  /// which picks the right end per theme; it is also the theme pill's "on" track and the
  /// dark-theme field of the gold CTA, where it takes an [inkNavy] label (DECISIONS §15).
  /// Ironclad value: a rich brass at 6.5:1 on the night cards.
  static const goldDeepDark = Color(0xFFD6AD5B);

  // Nav rail (v2.2): deep green field with a gold icon accent.
  static const railGreen = Color(0xFF24382F); // nav rail background
  static const railIcon = Color(0xFFC89A4E); // rail icon / active accent

  // Semantic (muted) — tuned as FILLS: button fields, chart segments, borders, seals.
  // Two carve-outs, both from DECISIONS §14: status dots read as type and take the
  // matching `*Ink` token, not these; and a fill carrying a *label* still owes the type
  // bar, so the success snackbar takes successDeep instead of `success` (WasiatiSnack).
  static const success = Color(0xFF2F7D5B);
  static const warning = Color(0xFFB4791F);
  static const danger = Color(0xFF9E3B2E); // muted brick, never pure red/black
  static const info = Color(0xFF3A5673);

  /// Semantic *type*: the readable ink ends for semantic text and glyphs.
  ///
  /// The constants above are fills, where contrast barely matters. As type they are
  /// a different job, and each fails AA somewhere: on nightSurface `danger` is
  /// 2.28:1, `success` 3.08:1, `warning` 4.17:1, `info` 2.02:1. `warning` is worse
  /// still on parchmentLight (3.22:1) — the surface it was assumed safe on — and
  /// drops to 2.85:1 on its own `warningTintLight` chip.
  ///
  /// Unlike `--goldDeep`, the prototype does NOT theme-swap `--success/--warning/
  /// --danger/--info`, so it carries this defect too; splitting ink from fill here is
  /// a deliberate deviation for accessibility (DECISIONS §14), not a transcription.
  ///
  /// Read them through `context.tokens.dangerInk` / `.successInk` / `.warningInk` /
  /// `.infoInk`, which pick the right end per theme. Naming follows the gold/green
  /// scales: `Soft` = the lightened end (dark-theme ink), `Deep` = the darkened end
  /// (light-theme ink). `danger` and `info` need no `Deep` — they already read on
  /// parchmentLight (5.87:1 / 6.64:1), so each is its own light ink.
  ///
  /// The dark ends hold their fill's hue and saturation and lift only HSL lightness,
  /// so a state keeps its identity across themes; they are tuned against
  /// `nightRaised`, the harder of the two dark fields, not `nightSurface`.
  static const dangerSoft = Color(0xFFD57C70); // 5.08:1 on nightSurface
  static const infoSoft = Color(0xFF7798BB); // 5.11:1 on nightSurface

  /// Doubles as the success snackbar's field — the one fill tuned by what sits ON it
  /// (`onDark`, 4.91:1) rather than what it sits on. Re-tune it for light-theme type
  /// and the snack moves too; theme_contrast_test pins both jobs.
  static const successDeep = Color(0xFF2B7253); // 5.04:1 on parchmentLight · 4.91:1 under onDark
  static const successSoft = Color(0xFF3EA679); // 5.07:1 on nightSurface
  static const warningDeep = Color(0xFF885C18); // 5.10:1 on parchmentLight
  static const warningSoft = Color(0xFFDD9C38); // 6.50:1 on nightSurface

  /// The record/live accent: the dot on a "Record video" button. Three sites — the
  /// will's video step, the legacy card, and the record screen's idle button.
  ///
  /// A red, but deliberately not [danger]. The prototype holds the two apart —
  /// every other colour in the record button is a variable (`background:var(--btn)`,
  /// `color:var(--btnText)`) while the dot alone is a literal `#C46B5C`; ten lines
  /// on, "Stop & save" is `#C46B5C` where "Delete" is `var(--danger)`. Capture is
  /// not destruction. The app had transcribed [danger] here, which is both the
  /// wrong semantic and, at 1.44:1 on the button, an invisible one.
  ///
  /// Flat rather than a theme-swapped ink (cf. [goldDeep]/[goldDeepDark]): the dot
  /// sits on the green button field in *both* themes, so there is no light or dark
  /// end to choose between. The prototype never theme-swaps it either.
  ///
  /// **The indicator — dots, borders, tints.** These carry no label, so they are
  /// exempt from the type bar; this is the prototype's exact `#C46B5C`. For the one
  /// place that DOES carry a label — the stop button — use [recordStopField], not this
  /// (no ink clears 4.5 on `#C46B5C`; [inkNavy], the darkest, reaches only 4.19).
  static const record = Color(0xFFC46B5C);

  /// The stop button's fill: the record red deepened just enough to carry [onDark] at
  /// **4.94:1**, so the "Stop" label clears AA (DECISIONS §14 addendum, owner: keep the
  /// prototype's red, make the label read — a red stop control is the universal
  /// recording convention, so it stays red rather than becoming `scheme.primary`).
  /// It is close to [danger] in luminance but a warmer terracotta, and the two never
  /// share a surface — the record screen shows no `danger`. Pairs with a stop-square
  /// icon (WCAG 1.4.11 graphical, 3:1) so the affordance never rests on the label alone.
  static const recordStopField = Color(0xFFA5493A); // 4.94:1 under onDark

  // Text neutrals on parchment (no pure black).
  //
  // "Ironclad" tier (owner pick, DECISIONS §22). The owner rejected several readable-but-
  // subtle passes as still too faint and asked for MAXIMUM legibility, so the greys are
  // pushed close to the primary ink: the tiers are told apart by weight and size, not by
  // fading. Warm neutral (no green cast). Quoted at their worst light surface (#F5EFE1).
  static const onLight = inkNavy; // primary text — 11.8:1
  static const onLightMuted = Color(0xFF454036); // secondary / muted text — 9.0:1
  static const onLightFaint = Color(0xFF524B40); // captions — 7.5:1
  static const onDark = Color(0xFFF3ECDC); // text on green/navy surfaces
  static const outline = Color(0x242F4A3D); // hairline rgba(47,74,61,.14)

  // --- Dark ("Night green") — no pure black anywhere -----------------------
  static const nightBg = Color(0xFF151C18); // background
  static const nightSurface = Color(0xFF1E2721); // cards
  static const nightRaised = Color(0xFF253029); // raised / emphasis cards
  static const darkText = Color(0xFFECE3D0); // primary text (parchment) — 10.7:1
  // Ironclad tier (DECISIONS §22): warm bones pushed close to the primary text and stripped
  // of the old green tint — the owner found #9DB3A4 / #7E9587 murky and unreadable.
  static const darkTextMuted = Color(0xFFD5D1C7); // secondary text — 9.0:1
  static const darkTextFaint = Color(0xFFC5C0B2); // inactive nav, captions — 7.5:1
  static const darkPrimaryButton = Color(0xFF4A6B5A); // primary CTA on dark
  static const darkBorder = Color(0x1FECE3D0); // hairline rgba(236,227,208,.12)
  // Gold accents are shared across themes (goldSoft / brassGold).

  // --- Translucent accent borders / tints ----------------------------------
  // Semi-transparent variants of the brand colours, used to outline callouts and
  // highlighted cards in BOTH themes. Named here so a palette change is one edit
  // rather than a hunt for `Color(0x66A87B33)` scattered through the screens.
  static const goldBorderSoft = Color(0x40A87B33); // brassGold @ 25%
  static const goldBorder = Color(0x66A87B33); // brassGold @ 40%
  static const goldBorderStrong = Color(0x73A87B33); // brassGold @ 45%
  static const greenBorder = Color(0x662F4A3D); // bottleGreen @ 40%
  static const dangerBorder = Color(0x559E3B2E); // danger @ 33%
  static const warningTintLight = Color(0x1FB4791F); // warning @ 12%
  static const warningTintDark = Color(0x33B4791F); // warning @ 20%
}
