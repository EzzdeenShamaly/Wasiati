import 'package:flutter/widgets.dart';
import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart';

/// Terse access to the current [AppLocalizations]: `context.l10n.navHome`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// True when the active locale renders right-to-left (Arabic).
  bool get isRtl => Directionality.of(this) == TextDirection.rtl;

  /// [localizeDigits] against the active locale. Wrap any UI string that carries a
  /// COMPUTED number so it reads in the locale's own digits:
  /// `context.digits(l.dashHeirCount(n))`, `context.digits(formatMoney(...))`.
  String digits(String text) => localizeDigits(text, Localizations.localeOf(this).languageCode);
}

/// Arabic-Indic digits ٠–٩, indexed by their Western value.
const _arabicIndicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// Maps the ASCII digits 0–9 in [text] to the [languageCode] locale's digit set — today
/// Arabic-Indic under `ar`, identity for every other locale.
///
/// The app's Arabic copy is written in Arabic-Indic throughout — WASIATI_HANDOFF requires
/// "Arabic numerals (٠١٢…) in AR locale", and the ARB literals honour it — but nothing the
/// app *computes* arrives that way: neither intl's `ar` NumberFormat, nor
/// MaterialLocalizations.formatDecimal, nor a bare `'$n'` yields Arabic-Indic (all return
/// Western digits under `ar`). So every number injected into an Arabic sentence is mapped
/// here at the point of display, or it reads in the wrong system beside the static copy.
///
/// Touches only ASCII digits, so it is idempotent (Arabic-Indic digits pass through) and
/// leaves currency codes, separators and letters alone — safe to wrap a whole composed
/// string such as a formatted price. It does NOT belong on identifiers meant to stay
/// Western (phone numbers, IBANs, OTP/promo codes) — wrap the quantity, not the identifier.
String localizeDigits(String text, String languageCode) {
  if (languageCode != 'ar') return text;
  return text.replaceAllMapped(RegExp(r'[0-9]'), (m) => _arabicIndicDigits[m[0]!.codeUnitAt(0) - 0x30]);
}

/// Localised heir-relation label from the API code (HUSBAND, WIFE, …). Shared by
/// the wills screens so relations read identically and mirror in Arabic.
String heirRelLabel(AppLocalizations l, String api) => switch (api) {
      'HUSBAND' => l.relHusband,
      'WIFE' => l.relWife,
      'SON' => l.relSon,
      'DAUGHTER' => l.relDaughter,
      'SON_SON' => l.relSonSon,
      'SON_DAUGHTER' => l.relSonDaughter,
      'FATHER' => l.relFather,
      'MOTHER' => l.relMother,
      'GRANDFATHER' => l.relGrandfather,
      'PATERNAL_GRANDMOTHER' => l.relPaternalGrandmother,
      'MATERNAL_GRANDMOTHER' => l.relMaternalGrandmother,
      'GRANDMOTHER' => l.relGrandmother,
      'FULL_BROTHER' => l.relBrother,
      'FULL_SISTER' => l.relSister,
      'CONSANGUINE_BROTHER' => l.relConsanguineBrother,
      'CONSANGUINE_SISTER' => l.relConsanguineSister,
      'MATERNAL_SIBLING' => l.relMaternalSibling,
      'FULL_NEPHEW' => l.relFullNephew,
      'CONSANGUINE_NEPHEW' => l.relConsanguineNephew,
      'FULL_UNCLE' => l.relFullUncle,
      'CONSANGUINE_UNCLE' => l.relConsanguineUncle,
      'FULL_COUSIN' => l.relFullCousin,
      'CONSANGUINE_COUSIN' => l.relConsanguineCousin,
      // Not a person: the public treasury, which takes the surplus under Maliki and
      // Shafi'i, or when nobody but a spouse survives.
      'BAYT_AL_MAL' => l.relBaytAlMal,
      _ => api,
    };
