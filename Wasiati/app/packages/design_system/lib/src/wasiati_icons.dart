import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A single Wasiati UI icon rendered from raw SVG markup.
///
/// Icons are transcribed from the Wasiati prototype's inline `<svg>` line marks
/// (thin stroke, rounded caps/joins, 24×24 grid) so the app matches the design
/// exactly. Every glyph in [WasiatiIcons] uses `currentColor`, so [WasiatiIcon]
/// can tint it like a font icon via a [ColorFilter]. When [color] is null the
/// icon inherits the ambient [DefaultTextStyle] colour (falling back to the
/// current [IconTheme] colour), matching how `Icon` behaves.
class WasiatiIcon extends StatelessWidget {
  /// Raw SVG markup — use a constant from [WasiatiIcons].
  final String svg;

  /// Rendered width and height in logical pixels.
  final double size;

  /// Tint applied to the whole glyph. Defaults to the inherited text/icon colour.
  final Color? color;

  /// Optional semantics label for screen readers.
  final String? semanticLabel;

  const WasiatiIcon({
    super.key,
    required this.svg,
    this.size = 22,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        DefaultTextStyle.of(context).style.color ??
        IconTheme.of(context).color ??
        const Color(0xFF1C2333);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}

/// The Wasiati icon catalogue — SVG strings transcribed from the prototype's own
/// line icons (24x24, currentColor) so the app matches the design exactly.
/// chevronRight/back/add are drawn to match (the prototype uses text glyphs).
class WasiatiIcons {
  WasiatiIcons._();
  static const String home = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 10.5 L12 3 l9 7.5"></path><path d="M5 9.5 V21 h14 V9.5"></path></svg>''';
  static const String wills = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M7 3 h10 a2 2 0 0 1 2 2 v16 l-3 -2 -4 2 -4 -2 -3 2 V5 a2 2 0 0 1 2 -2 z"></path><path d="M9 8 h6 M9 12 h6"></path></svg>''';
  static const String vault = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="10" width="16" height="11" rx="2"></rect><path d="M8 10 V7 a4 4 0 0 1 8 0 v3"></path></svg>''';
  static const String burial = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 C8 7 6 10 6 13 a6 6 0 0 0 12 0 c0 -3 -2 -6 -6 -10 z"></path></svg>''';
  static const String guided = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12 c0 4.4 -4 8 -9 8 c-1.2 0 -2.4 -.2 -3.4 -.6 L3 21 l1.7 -4.3 C3.6 15.4 3 13.8 3 12 c0 -4.4 4 -8 9 -8 s9 3.6 9 8 z"></path></svg>''';
  static const String identity = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"></rect><circle cx="8.5" cy="11" r="2"></circle><path d="M13.5 9.5 h4 M13.5 13 h4 M5.8 16 c.6 -1.6 4.8 -1.6 5.4 0"></path></svg>''';
  static const String plans = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12 l-8 8 -8.5 -8.5 V4 h7.5 z"></path><circle cx="7.5" cy="7.5" r="1.4"></circle></svg>''';
  static const String settings = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M12 2 v3 M12 19 v3 M2 12 h3 M19 12 h3 M4.5 4.5 l2 2 M17.5 17.5 l2 2 M4.5 19.5 l2 -2 M17.5 6.5 l2 -2"></path></svg>''';
  static const String admin = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7.5" height="7.5" rx="1.5"></rect><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.5"></rect><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.5"></rect><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.5"></rect></svg>''';
  static const String users = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.2"></circle><path d="M3.5 20 c.8 -3.6 3.4 -5 5.5 -5 s4.7 1.4 5.5 5"></path><path d="M16 5.5 a3.2 3.2 0 0 1 0 5.5 M18 15.5 c1.4 .8 2.3 2.3 2.6 4.5"></path></svg>''';
  static const String claims = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5 h11 M9 12 h11 M9 19 h11"></path><path d="M4 4.5 l1 1 2 -2 M4 11.5 l1 1 2 -2 M4 18.5 l1 1 2 -2"></path></svg>''';
  static const String heirContacts = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21 v-2 a4 4 0 0 0 -4 -4 H5 a4 4 0 0 0 -4 4 v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21 v-2 a4 4 0 0 0 -3 -3.87"></path><path d="M16 3.13 a4 4 0 0 1 0 7.75"></path></svg>''';
  static const String witnesses = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11 l3 3 8 -8"></path><path d="M20 12 v6 a2 2 0 0 1 -2 2 H6 a2 2 0 0 1 -2 -2 V6 a2 2 0 0 1 2 -2 h9"></path></svg>''';
  static const String trustee = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 l8 3.5 V12 c0 4.5 -3.5 7.5 -8 9 c-4.5 -1.5 -8 -4.5 -8 -9 V6.5 z"></path><path d="M9 12 l2 2 4 -4.5"></path></svg>''';
  static const String chevronRight = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6 l6 6 -6 6"></path></svg>''';
  static const String back = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12 H5 M12 19 l-7 -7 7 -7"></path></svg>''';
  static const String add = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5 v14 M5 12 h14"></path></svg>''';
  static const String edit = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3 l4 4 L8 20 l-5 1 1 -5 z"></path></svg>''';
  static const String download = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 v12 M7 10 l5 5 5 -5"></path><path d="M4 19 h16"></path></svg>''';
  static const String check = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 L9 17 l-5 -5"></path></svg>''';
  static const String mic = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="3" width="6" height="11" rx="3"></rect><path d="M5 11 a7 7 0 0 0 14 0"></path><path d="M12 18 v3"></path></svg>''';
  static const String signOut = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M15 4 h-8 a2 2 0 0 0 -2 2 v12 a2 2 0 0 0 2 2 h8"></path><path d="M11 12 h9 M17 8.5 l3.5 3.5 -3.5 3.5"></path></svg>''';

  // --- Theme-switch glyphs ---------------------------------------------------
  // The two 8×8 marks that ride inside the theme pill's knob. Transcribed from
  // the prototype's `toggleTheme` markup verbatim, so they keep their own weights
  // rather than the 1.9 stroke the nav glyphs above share: the sun is a 2.6-stroke
  // line mark (it has to stay legible at 8px), and the moon is a solid fill.

  /// Sun — shown while the app is in LIGHT mode. Stroke-only, stroke-width 2.6.
  static const String sun = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><circle cx="12" cy="12" r="4"></circle><path d="M12 2 v2 M12 20 v2 M2 12 h2 M20 12 h2 M4.9 4.9 l1.4 1.4 M17.7 17.7 l1.4 1.4 M4.9 19.1 l1.4 -1.4 M17.7 6.3 l1.4 -1.4"></path></svg>''';

  /// Moon — shown while the app is in DARK mode. Solid fill, no stroke.
  static const String moon = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M20 14 A8.5 8.5 0 0 1 10 4 a8 8 0 1 0 10 10 z"></path></svg>''';
}
