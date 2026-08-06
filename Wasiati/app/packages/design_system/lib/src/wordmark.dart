import 'package:flutter/material.dart';
import 'colors.dart';
import 'seal.dart';
import 'typography.dart';

/// "Wasiati" (Fraunces 600) with وصيتي in gold beneath — the bilingual wordmark.
class WasiatiWordmark extends StatelessWidget {
  final double size; // font size of the Latin wordmark
  final bool showArabic;
  final Color? color;

  const WasiatiWordmark({super.key, this.size = 28, this.showArabic = true, this.color});

  @override
  Widget build(BuildContext context) {
    final onSurface = color ?? Theme.of(context).colorScheme.onSurface;
    final gold = Theme.of(context).brightness == Brightness.dark ? WasiatiColors.goldSoft : WasiatiColors.brassGold;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Wasiati',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontSize: size, color: onSurface, letterSpacing: -0.3),
        ),
        if (showArabic) ...[
          const SizedBox(height: 2),
          Text('وصيتي', style: WasiatiType.arabic(TextStyle(fontSize: size * 0.7, color: gold, height: 1.7))),
        ],
      ],
    );
  }
}

/// Brand lockup: the signed-W [WasiatiSeal] above the [WasiatiWordmark]. Used on
/// splash, welcome, and auth.
class WasiatiLogo extends StatelessWidget {
  final double sealSize;
  final double wordSize;
  final bool showArabic;

  const WasiatiLogo({super.key, this.sealSize = 64, this.wordSize = 30, this.showArabic = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WasiatiSeal(size: sealSize),
        const SizedBox(height: 16),
        WasiatiWordmark(size: wordSize, showArabic: showArabic),
      ],
    );
  }
}
