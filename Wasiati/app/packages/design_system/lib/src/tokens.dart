import 'package:flutter/material.dart';
import 'colors.dart';

/// Brand colours that Material's [ColorScheme] has no slot for.
///
/// These used to be re-declared as private `_muted(context)` / `_faint(context)` /
/// `_hairline(context)` helpers in every screen — sixteen identical copies, each of
/// which had to be found and edited whenever the palette moved. They live here now,
/// resolved by theme rather than by re-reading [Theme.of] brightness at each call.
///
/// Read them through the [WasiatiTokensX] extension:
/// ```dart
/// Text('…', style: t.bodySmall?.copyWith(color: context.tokens.muted));
/// ```
@immutable
class WasiatiTokens extends ThemeExtension<WasiatiTokens> {
  /// Secondary text: labels, subtitles, supporting copy.
  final Color muted;

  /// Captions, inactive nav, timestamps — one step quieter than [muted].
  final Color faint;

  /// The 1px divider/border colour. Never a full-strength line.
  final Color hairline;

  /// Card and raised-surface fills, for the cases `Card` itself is not used.
  final Color card;
  final Color raised;

  /// Brass gold — focus rings, badges, active accents. Unchanged across themes.
  final Color gold;

  /// The green "highlighted box" fill: checklist rows, region chips, the callout
  /// panels that sit ON a card and need to read as *selected* rather than as a
  /// second card.
  ///
  /// [WasiatiColors.greenTint] is a LIGHT-theme fill and nothing else. Left
  /// unconditional it burns a pale, cold, near-white panel into a night card —
  /// the "baby blue boxes in dark mode" bug report — and it is the same constant
  /// the light theme uses for `primaryContainer`, so it cannot simply be
  /// re-tuned: darkening it to fix dark would wreck light. Hence the split, with
  /// the light end held EXACTLY at the value light mode already shipped.
  ///
  /// Screens had been open-coding `dark ? greenDeep : greenTint` one at a time;
  /// this is that pair, named once, so the next highlighted box gets it for free.
  final Color highlight;

  /// Green *type*: the readable ink for brand-green text and glyphs on a theme
  /// surface — checklist labels, active tab labels, "live"/"standard" status text.
  ///
  /// Same ink/fill split as [goldInk] and the semantic inks, and the same bug:
  /// [WasiatiColors.bottleGreen] is 1.59:1 on `nightSurface` and the prototype's
  /// own dark green ([WasiatiColors.greenSoft]) only reaches 2.59:1, so green
  /// copy in dark mode was unreadable wherever a screen hard-coded the light ink
  /// (owner: "in dark mode any green fonts should be in white").
  ///
  /// The dark end is therefore NOT a lighter green — no point on the brand green
  /// scale clears AA on a night card — it is [WasiatiColors.darkText], the
  /// established on-dark parchment ink (12.19:1 on `nightSurface`). The light end
  /// is `bottleGreen` unchanged, so light mode does not move at all.
  final Color greenInk;

  /// Gold *type*: the readable ink for gold-toned text and glyphs sitting on a
  /// theme surface (a card, or a `brassGold @ 10%` wash over one).
  ///
  /// This is the prototype's `--goldDeep`, which it theme-swaps rather than holds
  /// constant. The app had transcribed only the light value and used it in both
  /// themes, which is what made gold copy "barely readable" on dark: `goldDeep` on
  /// nightSurface is 2.81:1. Swapping to the dark end restores 6.55:1.
  ///
  /// Deliberately NOT [gold]: the accent gold is tuned for fills and 1px rings,
  /// where contrast barely matters. As body type it fails AA on the light end too —
  /// `brassGold` on parchmentLight is only 3.30:1, where `goldDeep` gives 4.76:1.
  final Color goldInk;

  /// Semantic *type*: the readable inks for danger/success/warning/info text and glyphs.
  ///
  /// Same split as [goldInk], for the same reason. `WasiatiColors.danger` and friends
  /// are fills — a snackbar field, a chart segment, a 1px border — and as body type they
  /// fail AA: danger is 2.28:1 on nightSurface, success 3.08:1, warning 4.17:1, and
  /// info 2.02:1. Keep using the raw constants for those fills; use these for anything
  /// a user reads.
  ///
  /// Both ends move, not just the dark one: `warning` as light-theme type is 3.22:1 on
  /// parchmentLight — a worse miss than its dark case — so [warningInk] darkens on
  /// light and lightens on dark. [dangerInk] and [infoInk] keep their raw constant as
  /// the light end (5.87:1 / 6.64:1) and only lighten for dark.
  final Color dangerInk;
  final Color successInk;
  final Color warningInk;
  final Color infoInk;

  const WasiatiTokens({
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.card,
    required this.raised,
    required this.gold,
    required this.highlight,
    required this.greenInk,
    required this.goldInk,
    required this.dangerInk,
    required this.successInk,
    required this.warningInk,
    required this.infoInk,
  });

  static const light = WasiatiTokens(
    muted: WasiatiColors.onLightMuted,
    faint: WasiatiColors.onLightFaint,
    hairline: WasiatiColors.outline,
    card: WasiatiColors.parchmentLight,
    raised: WasiatiColors.parchmentDeep,
    gold: WasiatiColors.brassGold,
    highlight: WasiatiColors.greenTint,
    greenInk: WasiatiColors.bottleGreen,
    goldInk: WasiatiColors.goldDeep,
    dangerInk: WasiatiColors.danger,
    successInk: WasiatiColors.successDeep,
    warningInk: WasiatiColors.warningDeep,
    infoInk: WasiatiColors.info,
  );

  static const dark = WasiatiTokens(
    muted: WasiatiColors.darkTextMuted,
    faint: WasiatiColors.darkTextFaint,
    hairline: WasiatiColors.darkBorder,
    card: WasiatiColors.nightSurface,
    raised: WasiatiColors.nightRaised,
    gold: WasiatiColors.goldSoft,
    highlight: WasiatiColors.greenDeep,
    greenInk: WasiatiColors.darkText,
    goldInk: WasiatiColors.goldDeepDark,
    dangerInk: WasiatiColors.dangerSoft,
    successInk: WasiatiColors.successSoft,
    warningInk: WasiatiColors.warningSoft,
    infoInk: WasiatiColors.infoSoft,
  );

  @override
  WasiatiTokens copyWith({
    Color? muted,
    Color? faint,
    Color? hairline,
    Color? card,
    Color? raised,
    Color? gold,
    Color? highlight,
    Color? greenInk,
    Color? goldInk,
    Color? dangerInk,
    Color? successInk,
    Color? warningInk,
    Color? infoInk,
  }) =>
      WasiatiTokens(
        muted: muted ?? this.muted,
        faint: faint ?? this.faint,
        hairline: hairline ?? this.hairline,
        card: card ?? this.card,
        raised: raised ?? this.raised,
        gold: gold ?? this.gold,
        highlight: highlight ?? this.highlight,
        greenInk: greenInk ?? this.greenInk,
        goldInk: goldInk ?? this.goldInk,
        dangerInk: dangerInk ?? this.dangerInk,
        successInk: successInk ?? this.successInk,
        warningInk: warningInk ?? this.warningInk,
        infoInk: infoInk ?? this.infoInk,
      );

  @override
  WasiatiTokens lerp(ThemeExtension<WasiatiTokens>? other, double t) {
    if (other is! WasiatiTokens) return this;
    return WasiatiTokens(
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      card: Color.lerp(card, other.card, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      greenInk: Color.lerp(greenInk, other.greenInk, t)!,
      goldInk: Color.lerp(goldInk, other.goldInk, t)!,
      dangerInk: Color.lerp(dangerInk, other.dangerInk, t)!,
      successInk: Color.lerp(successInk, other.successInk, t)!,
      warningInk: Color.lerp(warningInk, other.warningInk, t)!,
      infoInk: Color.lerp(infoInk, other.infoInk, t)!,
    );
  }
}

extension WasiatiTokensX on BuildContext {
  /// Brand tokens for the active theme. Falls back to the light set if the theme
  /// was built without the extension (e.g. a bare `ThemeData()` in a widget test),
  /// so a screen can always render rather than throwing on a null.
  WasiatiTokens get tokens => Theme.of(this).extension<WasiatiTokens>() ?? WasiatiTokens.light;
}
