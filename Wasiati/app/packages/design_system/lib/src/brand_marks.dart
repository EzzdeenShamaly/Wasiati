import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Third-party sign-in marks (Google, Apple).
///
/// Deliberately NOT part of [WasiatiIcons]: that catalogue is our own line icons
/// transcribed from the prototype, all drawn with `currentColor` so [WasiatiIcon] can
/// tint them with `BlendMode.srcIn`. Brand marks cannot go through that path —
/// flattening Google's four-colour G to a single ink would breach their brand terms,
/// which require the logo in its own colours and forbid recolouring it.
///
/// So the two marks are treated differently, matching each vendor's guidelines:
/// Google's G always renders in full colour; Apple's mark is monochrome by design and
/// takes the button's foreground colour, so it stays legible in light and dark.
class WasiatiBrandMark extends StatelessWidget {
  final String _svg;
  final double size;

  /// Non-null only for marks that are allowed to take the surrounding ink (Apple).
  final Color? _tint;

  const WasiatiBrandMark._(this._svg, {required this.size, Color? tint}) : _tint = tint;

  /// Google's four-colour G. Never recoloured — the colours are the mark.
  factory WasiatiBrandMark.google({double size = 20}) =>
      WasiatiBrandMark._(_googleG, size: size);

  /// Apple's mark, monochrome. Pass the button's foreground colour so it inverts
  /// correctly between the parchment and night themes.
  factory WasiatiBrandMark.apple({double size = 20, Color? color}) =>
      WasiatiBrandMark._(_appleMark, size: size, tint: color);

  @override
  Widget build(BuildContext context) {
    final resolved = _tint == null
        ? null
        : ColorFilter.mode(
            // Fall back to the inherited ink so the mark is never invisible.
            _tint,
            BlendMode.srcIn,
          );
    return ExcludeSemantics(
      // The button already carries its own label ("Continue with Apple"), so the
      // mark must not announce itself a second time.
      child: SvgPicture.string(_svg, width: size, height: size, colorFilter: resolved),
    );
  }
}

/// Google's "G", official four-colour artwork.
const String _googleG = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24s.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

/// Apple's mark. Monochrome by specification — takes the surrounding ink.
const String _appleMark =
    r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M17.05 12.94c-.02-2.6 2.12-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.9-1.74.03-3.35 1.01-4.25 2.57-1.81 3.14-.46 7.79 1.3 10.34.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84s2.01.84 3.39.81c1.4-.02 2.28-1.27 3.13-2.53.99-1.45 1.4-2.85 1.42-2.92-.03-.01-2.72-1.04-2.75-4.12M14.5 4.6c.71-.87 1.19-2.07 1.06-3.27-1.02.04-2.26.68-3 1.54-.66.76-1.24 1.98-1.08 3.15 1.14.09 2.3-.58 3.02-1.42"/></svg>''';
