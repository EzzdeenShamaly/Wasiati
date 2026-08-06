import 'package:flutter/material.dart';

/// Typography: Fraunces (display), Public Sans (body), IBM Plex Sans Arabic
/// (Arabic UI), Amiri (Qur'an/hadith serif).
///
/// The .ttf assets are bundled by the app (see apps/wasiati/pubspec.yaml) so the
/// design's type renders instantly and offline — no runtime font fetch. Fraunces
/// and Public Sans are variable fonts; Flutter drives the wght axis from fontWeight.
///
/// Fraunces/Public Sans carry no Arabic glyphs, so every style falls back to
/// IBM Plex Sans Arabic (then Amiri) — that way Arabic copy rendered through a
/// display/body style still resolves to the Arabic UI face instead of tofu or
/// the classical serif.
abstract final class WasiatiType {
  static const displayFamily = 'Fraunces';
  static const bodyFamily = 'Public Sans';
  // Arabic UI/body = IBM Plex Sans Arabic (v2.2, replaces Almarai); Qur'an &
  // hadith (classical serif) = Amiri.
  static const arabicFamily = 'IBM Plex Sans Arabic';
  static const arabicSerifFamily = 'Amiri';

  // Arabic fallback for the Latin faces: IBM Plex Sans Arabic (UI) first, Amiri
  // only for rare marks.
  static const _arabicFallback = [arabicFamily, arabicSerifFamily];

  static TextStyle _fraunces(TextStyle s) =>
      s.copyWith(fontFamily: displayFamily, fontFamilyFallback: _arabicFallback);
  static TextStyle _publicSans(TextStyle s) =>
      s.copyWith(fontFamily: bodyFamily, fontFamilyFallback: _arabicFallback);

  /// Arabic UI/body (IBM Plex Sans Arabic). Use for Arabic (RTL) interface text.
  static TextStyle arabic(TextStyle s) => s.copyWith(fontFamily: arabicFamily);

  /// Classical Arabic serif (Amiri) — for Qur'an ayat and hadith.
  static TextStyle arabicSerif(TextStyle s) => s.copyWith(fontFamily: arabicSerifFamily);

  static TextTheme textTheme(Color onSurface, Color muted) {
    TextStyle disp(double size, {FontWeight w = FontWeight.w600, double? h}) =>
        _fraunces(TextStyle(fontSize: size, fontWeight: w, height: h, color: onSurface, letterSpacing: -0.2));
    TextStyle body(double size, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
        _publicSans(TextStyle(fontSize: size, fontWeight: w, height: h ?? 1.45, color: c ?? onSurface));

    return TextTheme(
      displayLarge: disp(52, h: 1.05),
      displayMedium: disp(42, h: 1.08),
      displaySmall: disp(34, h: 1.1),
      headlineLarge: disp(30, h: 1.15),
      headlineMedium: disp(25, h: 1.2),
      headlineSmall: disp(21, w: FontWeight.w600, h: 1.25),
      titleLarge: body(19, w: FontWeight.w600),
      titleMedium: body(16, w: FontWeight.w600),
      titleSmall: body(14, w: FontWeight.w600),
      bodyLarge: body(17),
      bodyMedium: body(15),
      bodySmall: body(13, c: muted),
      labelLarge: body(15, w: FontWeight.w600),
      labelMedium: body(13, w: FontWeight.w600),
      labelSmall: body(12, w: FontWeight.w600, c: muted),
    );
  }
}
