import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Wasiati Material 3 themes — the approved "Parchment" light and "Night green"
/// dark. Parchment/night surfaces, bottle-green primary actions, brass-gold
/// highlights/focus, parchment-or-navy type. Rounded, calm, dignified. No pure
/// black in either theme.
abstract final class WasiatiTheme {
  static const _radius = 12.0; // buttons + inputs
  static const _cardRadius = 18.0;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: WasiatiColors.bottleGreen,
      onPrimary: WasiatiColors.onDark,
      primaryContainer: WasiatiColors.greenTint,
      onPrimaryContainer: WasiatiColors.greenDeep,
      secondary: WasiatiColors.brassGold,
      onSecondary: WasiatiColors.inkNavy,
      secondaryContainer: WasiatiColors.goldSoft,
      onSecondaryContainer: WasiatiColors.inkNavy,
      tertiary: WasiatiColors.goldDeep,
      onTertiary: WasiatiColors.onDark,
      error: WasiatiColors.danger,
      onError: WasiatiColors.onDark,
      surface: WasiatiColors.parchment,
      onSurface: WasiatiColors.inkNavy,
      // Full M3 surface ramp — menus/dropdowns/sheets read these; leaving any out
      // hands the widget a Material default instead of the brand parchment.
      surfaceDim: WasiatiColors.parchmentDeep,
      surfaceBright: WasiatiColors.parchmentLight,
      surfaceContainerLowest: WasiatiColors.parchmentLight,
      surfaceContainerLow: WasiatiColors.parchmentLight,
      surfaceContainer: WasiatiColors.parchmentLight,
      surfaceContainerHigh: WasiatiColors.parchmentDeep,
      surfaceContainerHighest: WasiatiColors.parchmentDeep,
      onSurfaceVariant: WasiatiColors.onLightMuted,
      outline: WasiatiColors.outline,
      outlineVariant: WasiatiColors.parchmentDeep,
      shadow: WasiatiColors.inkNavy,
    );
    return _build(
      scheme: scheme,
      text: WasiatiType.textTheme(WasiatiColors.inkNavy, WasiatiColors.onLightMuted),
      scaffold: WasiatiColors.parchment,
      appBarBg: WasiatiColors.parchment,
      cardColor: WasiatiColors.parchmentLight,
      inputFill: WasiatiColors.parchmentLight,
      primaryButtonBg: WasiatiColors.bottleGreen,
      hairline: WasiatiColors.outline,
      muted: WasiatiColors.onLightMuted,
      tokens: WasiatiTokens.light,
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: WasiatiColors.darkPrimaryButton,
      onPrimary: WasiatiColors.darkText,
      primaryContainer: WasiatiColors.greenDeep,
      onPrimaryContainer: WasiatiColors.darkText,
      secondary: WasiatiColors.goldSoft,
      onSecondary: WasiatiColors.nightBg,
      secondaryContainer: WasiatiColors.goldDeep,
      onSecondaryContainer: WasiatiColors.darkText,
      tertiary: WasiatiColors.brassGold,
      onTertiary: WasiatiColors.darkText,
      error: WasiatiColors.danger,
      onError: WasiatiColors.onDark,
      surface: WasiatiColors.nightSurface,
      onSurface: WasiatiColors.darkText,
      // The FULL M3 surface ramp must be supplied. Any token left out falls back to
      // Material's LIGHT default — that is what made menus, dropdowns (the madhhab
      // picker) and bottom sheets render WHITE in dark mode.
      surfaceDim: WasiatiColors.nightBg,
      surfaceBright: WasiatiColors.nightRaised,
      surfaceContainerLowest: WasiatiColors.nightBg,
      surfaceContainerLow: WasiatiColors.nightSurface,
      surfaceContainer: WasiatiColors.nightSurface,
      surfaceContainerHigh: WasiatiColors.nightRaised,
      surfaceContainerHighest: WasiatiColors.nightRaised,
      onSurfaceVariant: WasiatiColors.darkTextMuted,
      outline: WasiatiColors.darkBorder,
      outlineVariant: WasiatiColors.nightRaised,
      // Brand rule: no pure black anywhere. Use the darkest brand ink for elevation
      // shadows in dark mode instead of #000000.
      shadow: Color(0xFF0B0F0C),
    );
    return _build(
      scheme: scheme,
      text: WasiatiType.textTheme(WasiatiColors.darkText, WasiatiColors.darkTextMuted),
      scaffold: WasiatiColors.nightBg,
      appBarBg: WasiatiColors.nightBg,
      cardColor: WasiatiColors.nightSurface,
      inputFill: WasiatiColors.nightRaised,
      primaryButtonBg: WasiatiColors.darkPrimaryButton,
      hairline: WasiatiColors.darkBorder,
      muted: WasiatiColors.darkTextMuted,
      tokens: WasiatiTokens.dark,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required TextTheme text,
    required Color scaffold,
    required Color appBarBg,
    required Color cardColor,
    required Color inputFill,
    required Color primaryButtonBg,
    required Color hairline,
    required Color muted,
    required WasiatiTokens tokens,
  }) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // App-wide default family so any text without an explicit family (button
      // labels, custom TextStyles) renders in Public Sans, never platform Roboto.
      fontFamily: WasiatiType.bodyFamily,
      // Public Sans/Fraunces carry no Arabic glyphs, so any Arabic run NOT explicitly
      // wrapped in WasiatiType.arabic() (e.g. localized AR button/body copy) falls back
      // here. IBM Plex Sans Arabic FIRST = the Arabic UI face per v2.2 spec ("IBM Plex
      // Sans Arabic everywhere in AR");
      // Amiri only as a last resort for rare marks (e.g. the ʿayn in "rubʿ al-ʿushr").
      // Qur'anic text stays Amiri because it sets that family explicitly (arabicSerif()).
      fontFamilyFallback: const [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
      // Brand colours Material has no slot for. Read via `context.tokens`.
      extensions: <ThemeExtension<dynamic>>[tokens],
      scaffoldBackgroundColor: scaffold,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: border(hairline),
        enabledBorder: border(hairline),
        // focus = gold border + soft gold ring feel (via width bump).
        focusedBorder: border(WasiatiColors.brassGold, 1.8),
        errorBorder: border(WasiatiColors.danger),
        focusedErrorBorder: border(WasiatiColors.danger, 1.8),
        labelStyle: text.bodyMedium?.copyWith(color: muted),
        hintStyle: text.bodyMedium?.copyWith(color: muted),
        helperStyle: text.labelSmall?.copyWith(color: muted),
        // The borders above are 1px furniture and stay on the danger fill, but the
        // validation copy is type: Material would default errorStyle to scheme.error,
        // which is that same fill at 2.28:1 on a night card. Take the ink instead.
        errorStyle: text.labelSmall?.copyWith(color: tokens.dangerInk),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryButtonBg,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: primaryButtonBg.withValues(alpha: 0.38),
          disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.7),
          // Height-only: full-width CTAs get their width from a stretch Column or a
          // SizedBox(width: infinity). Size.fromHeight would force an INFINITE min
          // width, which is an unbounded-constraint crash inside a Row/Wrap.
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          elevation: 0,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // `scheme.primary` is a BUTTON FIELD, not type. In dark it is
          // darkPrimaryButton (== greenSoft), which as a label on a night surface
          // is 2.59:1 — the "green fonts are unreadable in dark mode" report, and
          // the one green that theming (rather than a screen) was producing.
          // greenInk is bottleGreen on light, so light mode is byte-identical.
          foregroundColor: tokens.greenInk,
          // Height-only (see ElevatedButton note) — full width comes from stretch,
          // never from an infinite min width that would crash in a Row/Wrap.
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          // The ring follows the label: a green ring around parchment type reads
          // as an unfinished control, and greenSoft on nightBg is 2.92:1 — under
          // the 3:1 WCAG 1.4.11 boundary the ring exists to satisfy.
          side: BorderSide(color: tokens.greenInk, width: 1.5),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.brightness == Brightness.dark ? WasiatiColors.goldSoft : WasiatiColors.goldDeep,
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: hairline),
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: text.labelSmall,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_cardRadius)),
      ),
      // Pop-out surfaces must be pinned to the brand card colour. Left unset they
      // take a Material default and render WHITE in dark mode — this is what showed
      // up on the madhhab dropdown, popup menus and the mobile "More" sheet.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_cardRadius)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(cardColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(cardColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    );
  }
}
