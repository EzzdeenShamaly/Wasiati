import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/router/back_nav.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

import '../../../core/l10n/l10n.dart';
import '../application/will_pdf.dart';
import '../application/wills_providers.dart';
import '../domain/will_export_gate.dart';
import 'will_preview_card.dart';

/// The will document, on its own page — the prototype's `willDoc` route ("Will export").
///
/// The document had no page of its own. It was the LAST child of the will-detail column,
/// under the header, the shares table, the bequests, the witnesses and the trustee panel —
/// below the fold on every viewport — and on the review screen it was squeezed into the
/// ~420px right-hand column directly beneath a Flutter-drawn mock of a will made of grey
/// bars. Two things that looked like the document on one screen, one of them decorative,
/// and the real one too narrow to read.
///
/// The prototype (lines 1685-1814) makes it one centred 660px column with nothing beside
/// it, and stacks the controls above the paper in a fixed order: back + download, then the
/// signing notice, then the two format toggles, then the document. That is this screen.
///
/// It keeps the navigation rail — `willDoc` is a normal in-app route in the prototype, not
/// one of the two focus routes (create, review) that hide the chrome.
class WillDocumentScreen extends ConsumerStatefulWidget {
  const WillDocumentScreen({super.key, required this.willId});
  final String willId;

  @override
  ConsumerState<WillDocumentScreen> createState() => _WillDocumentScreenState();
}

class _WillDocumentScreenState extends ConsumerState<WillDocumentScreen> {
  bool _downloading = false;

  /// Downloads exactly what is on screen. The format/display choice lives in
  /// willPreviewChoiceProvider precisely so the button cannot hand back a different
  /// document from the one just read.
  Future<void> _download() async {
    final choice = ref.read(willPreviewChoiceProvider);
    setState(() => _downloading = true);
    await shareWillPdf(
      context,
      ref,
      widget.willId,
      format: choice.format,
      display: choice.display,
      lang: Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en',
    );
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final will = ref.watch(willProvider(widget.willId));

    // Reading is never gated; only taking a copy away is. Resolved the same way as the
    // will-detail header (WillExportGate.of) so the two buttons cannot disagree.
    final gate = WillExportGate.of(
      requiredWitnesses: will.asData?.value.requiredWitnesses ?? 2,
      witnesses: ref.watch(witnessesProvider(widget.willId)).asData?.value,
      trustees: ref.watch(trusteesProvider(widget.willId)).asData?.value,
    );

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 860;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 38 : 18, vertical: wide ? 32 : 26) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                // 60% of the window, centered (owner, 27 Jul 2026 — revised from the
                // earlier 80%). Both views share the column: the live sheet fills it
                // with its enlarged base type (see WillDocumentSheet._fz), and the
                // "Page view" PDF pages render inside the same width. The back link
                // and Download button sit at the top of this same centered column.
                // Narrow viewports get the full width; the page padding is already
                // doing the margin there.
                constraints: BoxConstraints(maxWidth: wide ? box.maxWidth * 0.6 : box.maxWidth),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Back and download share one row, as in the prototype. The back link is
                  // OUTSIDE the async branches on purpose: a will that fails to load must
                  // still leave a way out, which is the bug on the screens this one replaces.
                  Row(children: [
                    Expanded(
                      child: WasiatiBackLink(
                        label: l.commonBackToWill,
                        onTap: () => context.goBack('/wills/${widget.willId}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: (_downloading || !gate.exportable) ? null : _download,
                      style: WasiatiButtons.goldSolid(context),
                      icon: _downloading
                          ? const SizedBox(
                              height: 15,
                              width: 15,
                              child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.onDark))
                          : const Icon(Icons.download_outlined, size: 17),
                      label: Text(l.wdDownloadPdf),
                    ),
                  ]),
                  // Why the download may be disabled, naming who is outstanding rather than
                  // leaving a dead button with no explanation.
                  if (gate.hasOutstanding) ...[
                    const SizedBox(height: 8),
                    Text(
                      _waitingOn(l, gate),
                      style: t.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(l.wdocTitle, style: t.headlineSmall),
                  const SizedBox(height: 4),
                  Text(l.wdocSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                  const SizedBox(height: 14),
                  // The prototype's green signing callout: how this document gets signed.
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                    decoration: BoxDecoration(
                      color: context.tokens.highlight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.tokens.hairline),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.draw_outlined, size: 17, color: context.tokens.greenInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l.wdocSigningNote,
                            style: t.bodySmall?.copyWith(color: context.tokens.greenInk, height: 1.5)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  will.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('$e', style: t.bodyMedium)),
                    ),
                    // The card already is the prototype's toggle row + helper line +
                    // divider + document, so it is reused whole rather than re-drawn.
                    // exportable: false — this page owns the download button above, and
                    // two of them on one screen is one too many.
                    data: (w) => WillPreviewCard(willId: w.id, exportable: false),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Names who is still outstanding. Mirrors the will-detail wording so the same wait is
  /// described the same way wherever it is met.
  String _waitingOn(AppLocalizations l, WillExportGate gate) {
    if (!gate.ready) return l.wdExportChecking;
    return [
      if (gate.outstandingWitnesses > 0) context.digits(l.wdExportWaitingWitnesses(gate.outstandingWitnesses)),
      if (gate.trusteeOutstanding) l.wdExportWaitingTrustee,
    ].join(' · ');
  }
}
