import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../content/application/content_providers.dart';

/// The sealed moment (design 10c): a quiet celebration once the will is sealed.
class SealedScreen extends ConsumerStatefulWidget {
  final String willId;
  const SealedScreen({super.key, required this.willId});

  @override
  ConsumerState<SealedScreen> createState() => _SealedScreenState();
}

class _SealedScreenState extends ConsumerState<SealedScreen> {
  @override
  Widget build(BuildContext context) {
    final willId = widget.willId;
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = context.tokens.goldInk;
    final faint = dark ? WasiatiColors.darkTextFaint : WasiatiColors.onLightFaint;

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            // Padding the content rather than the viewport keeps the seal card exactly
            // where it was: the scroll view shrink-wraps to content + bar, so Center
            // offsets it back above the glass. On a short screen it still scrolls clear.
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 40) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Seal(size: 110, status: SealStatus.sealed, filled: true),
                const SizedBox(height: 22),
                // The opening flourish — "Allāhumma bārik" (O Allah, bless) — sits large
                // above the title, per the design.
                Text('اللّهُمَّ بارِك',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: WasiatiType.arabic(
                        (t.headlineMedium ?? const TextStyle()).copyWith(color: gold, height: 1.4))),
                const SizedBox(height: 12),
                Text(l.sealTitle,
                    textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(height: 1.25)),
                const SizedBox(height: 18),
                // Admin-editable (spec §5): the wry line can be re-worded / re-toned
                // from the Content tab without a release. Falls back to the ARB value.
                Text(overrideText(ref, key: 'sealWry', fallback: l.sealWry, isRtl: context.isRtl),
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: faint, fontStyle: FontStyle.italic)),
                const SizedBox(height: 34),
                // One centered, wrapping row of three equal-height actions, per the
                // design: View will (filled) · Export PDF (gold outline) · Back to home.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton(
                      onPressed: () => context.go('/wills/$willId'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                      child: Text(l.sealViewWill),
                    ),
                    // Opens the document page, as the prototype's sealed screen does
                    // (navWillDoc). It used to call shareWillPdf() straight from here with
                    // no format/display, which dropped into the legacy export sheet AND
                    // skipped WillExportGate entirely — the one download path in the app
                    // that never asked whether the witnesses and trustee had confirmed.
                    // The document page owns that gate, so routing there closes the hole.
                    OutlinedButton(
                      onPressed: () => context.go('/wills/$willId/document'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: gold,
                        side: const BorderSide(color: WasiatiColors.brassGold, width: 1.5),
                        minimumSize: const Size(0, 50),
                      ),
                      child: Text(l.sealDownloadPdf),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/dashboard'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                      child: Text(l.sealBackHome),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
