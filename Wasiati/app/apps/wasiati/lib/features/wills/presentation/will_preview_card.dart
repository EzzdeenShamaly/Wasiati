import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../assets/application/assets_providers.dart';
import '../../auth/domain/auth_state.dart';
import '../application/wills_providers.dart';
import 'will_document_sheet.dart';

/// The will on the page, with the prototype's two controls above it: ESTATE FORMAT
/// (table | narrative) and SHARES AS (% | fraction).
///
/// ONE view, exactly like the prototype (owner, 27 Jul 2026 — "in prototype we only
/// have one view why do we have two"): the document rendered as live native text
/// ([WillDocumentSheet]), crisp at any size. There is no in-app page-view of the
/// PDF — the PDF is what the gated Download button hands back, built by the server
/// from the same design (will-document.service.ts), with the same toggles applied
/// through willPreviewChoiceProvider, so what is read here is what is kept.
///
/// An earlier iteration showed the server PDF as rasterised page bitmaps
/// (printing's PdfPreview) — scaled-down soft type, the owner's original "I can
/// barely read the fonts" complaint — and then kept it behind a "Page view"
/// toggle; both are gone.
///
/// Both toggles were already implemented server-side and reachable by nobody: the
/// pdf route has always accepted format/lang/display, and the app only ever sent
/// format and lang, so the spec's %-or-fractions choice had no way in. It does now.
class WillPreviewCard extends ConsumerWidget {
  const WillPreviewCard({super.key, required this.willId, this.exportable = true});

  final String willId;

  /// Whether the witnesses-and-trustee gate is satisfied. Only the DOWNLOAD is gated —
  /// reading your own will is not, which is what the prototype shows: the document on the
  /// page with the download button disabled above it.
  final bool exportable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final choice = ref.watch(willPreviewChoiceProvider);

    void choose(({String format, String display}) next) =>
        ref.read(willPreviewChoiceProvider.notifier).state = next;

    // No wrapping card: the prototype puts the toggle row directly on the page and
    // the document below it as a free-standing sheet of paper.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _ToggleGroup(
          label: l.wpEstateFormat,
          options: [(value: 'table', label: l.wpFormatTable), (value: 'essay', label: l.wpFormatNarrative)],
          selected: choice.format,
          onChanged: (v) => choose((format: v, display: choice.display)),
        ),
        _ToggleGroup(
          label: l.wpSharesAs,
          options: [
            (value: 'percent', label: l.wpSharesPercent),
            (value: 'fraction', label: l.wpSharesFraction),
          ],
          selected: choice.display,
          onChanged: (v) => choose((format: choice.format, display: v)),
        ),
      ]),
      const SizedBox(height: 8),
      Text(l.wpFormatHelp, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
      const SizedBox(height: 16),
      _DocumentBody(willId: willId, choice: choice),
    ]);
  }
}

/// The live document, assembled from the same providers the rest of the app reads.
class _DocumentBody extends ConsumerWidget {
  const _DocumentBody({required this.willId, required this.choice});

  final String willId;
  final ({String format, String display}) choice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final will = ref.watch(willProvider(willId));
    final assets = ref.watch(assetsProvider(willId));
    final witnesses = ref.watch(witnessesProvider(willId));
    final trustees = ref.watch(trusteesProvider(willId));
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.user : null;

    return will.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _Failed(onRetry: () => ref.invalidate(willProvider(willId))),
      data: (w) => WillDocumentSheet(
        will: w,
        assets: assets.asData?.value ?? const [],
        witnesses: witnesses.asData?.value ?? w.witnesses,
        trustees: trustees.asData?.value ?? const [],
        // Same derivation the server document uses (ownerEmail local-part), so the live
        // sheet and the downloaded PDF name the testator identically.
        testatorName: (user?.email ?? '').split('@').first,
        city: user?.addressCity,
        country: user?.addressCountry,
        format: choice.format,
        display: choice.display,
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: context.tokens.warningInk),
          const SizedBox(height: 10),
          Text(l.wpPreviewFailed, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l.wpPreviewRetry)),
        ]),
      ),
    );
  }
}

/// The prototype's segmented pill group: a small caps label, then the options.
class _ToggleGroup extends StatelessWidget {
  const _ToggleGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<({String value, String label})> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Text(
            label,
            style: t.bodySmall?.copyWith(
              color: context.tokens.faint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              fontSize: 11,
            ),
          ),
        ),
        // The prototype's segmented control (cycBtn, lines 3872-3874): one sunken
        // pill-shaped track, the active option a raised card-coloured pill with ink
        // text, the inactive ones bare muted text. No per-pill borders.
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: context.tokens.raised,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final o in options)
              _Pill(label: o.label, selected: o.value == selected, onTap: () => onChanged(o.value)),
          ]),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? context.tokens.card : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: t.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? Theme.of(context).colorScheme.onSurface : context.tokens.muted,
          ),
        ),
      ),
    );
  }
}
