import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../application/burial_providers.dart';
import '../domain/burial_models.dart';

/// Admin queue for burial quote requests, mirroring the death-claims queue.
///
/// The other half of "Request a real quote" (burial_screen): the client's press
/// flips their estimate to QUOTE_REQUESTED, and until this screen existed nothing
/// could ever answer it — the only list endpoint was scoped to the requester, so
/// the request sat unanswerable outside a notification email. The admin phones
/// mosques/funeral homes in the client's city and records the sourced price here;
/// the client sees it on their Burial page immediately.
class BurialQuotesAdminScreen extends ConsumerWidget {
  const BurialQuotesAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final queue = ref.watch(adminBurialQuotesProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: queue.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => ListView(
                // The bar's height rides on the content, so cards slide under the glass
                // mid-scroll and the last one still comes to rest clear of it.
                padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                children: [
                  Row(children: [
                    const Seal(size: 32, status: SealStatus.verified),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.bqEyebrow,
                            style: TextStyle(
                                color: context.tokens.goldInk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                        Text(l.bqTitle, style: t.headlineSmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(l.bqCareNote, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text(l.bqNoPending, style: t.bodyLarge?.copyWith(color: context.tokens.muted))),
                    )
                  else
                    for (final q in list) _QuoteCard(request: q),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteCard extends ConsumerWidget {
  final BurialQuoteRequest request;
  const _QuoteCard({required this.request});

  /// The dialog is a real StatefulWidget owning its controllers so they are
  /// disposed by the route's lifecycle — after the exit animation — not by this
  /// opener while the fields still render one last closing frame.
  Future<void> _recordQuote(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final e = request.estimate;
    final result = await showDialog<({double amount, String notes})>(
      context: context,
      builder: (_) => _QuoteDialog(estimate: e),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(burialApiProvider).adminSubmitQuote(e.id, amount: result.amount, notes: result.notes);
      ref.invalidate(adminBurialQuotesProvider);
      if (context.mounted) WasiatiSnack.success(context, l.bqQuoteSaved);
    } catch (err) {
      if (context.mounted) WasiatiSnack.danger(context, '$err'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final e = request.estimate;
    final waiting = e.status == 'QUOTE_REQUESTED';
    // Ink + label as one mark, matching the death-claims cards.
    final stColor = waiting ? context.tokens.warningInk : context.tokens.successInk;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Seal(size: 34, status: waiting ? SealStatus.locked : SealStatus.verified),
          const SizedBox(width: 12),
          // The CITY leads: the admin's task is "call around in Dearborn", and which
          // request is which city matters more at a glance than who asked.
          Expanded(child: Text('${e.city}, ${request.userRegion}', style: t.titleMedium)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: stColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(waiting ? l.bqStatusRequested : l.bqStatusQuoted,
                style: t.labelSmall?.copyWith(color: stColor, fontWeight: FontWeight.w700)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(l.bqRequestedBy(request.userPhone != null ? '${request.userEmail} · ${request.userPhone}' : request.userEmail),
            style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 2),
        Text(l.bqEstimateLine(e.money(e.baseAmount), e.money(e.projectedAmount), e.projectionYears),
            style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        if (e.manualQuoteAmount != null) ...[
          const SizedBox(height: 2),
          Text(l.bqQuotedLine(e.money(e.manualQuoteAmount!)),
              style: t.bodySmall?.copyWith(color: context.tokens.successInk, fontWeight: FontWeight.w600)),
          if (e.manualQuoteNotes?.isNotEmpty ?? false)
            Text(e.manualQuoteNotes!, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        ],
        const SizedBox(height: 14),
        if (waiting)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => _recordQuote(context, ref),
            child: Text(l.bqRecordQuote),
          )
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => _recordQuote(context, ref),
            child: Text(l.bqRecordQuote),
          ),
      ]),
    );
  }
}

/// Amount + notes form. Pops `(amount, notes)`; the opener owns the API call.
/// Pre-filled when re-recording over an existing quote — a typo'd amount must be
/// a two-keystroke fix (submitManualQuote happily overwrites).
class _QuoteDialog extends StatefulWidget {
  final BurialEstimate estimate;
  const _QuoteDialog({required this.estimate});
  @override
  State<_QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<_QuoteDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.estimate.manualQuoteAmount?.toStringAsFixed(0) ?? '');
    _notes = TextEditingController(text: widget.estimate.manualQuoteNotes ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = context.l10n.bqErrorAmountRequired);
      return;
    }
    Navigator.pop(context, (amount: v, notes: _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.bqQuoteDialogTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l.bqAmountLabel(widget.estimate.currency)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(labelText: l.bqNotesLabel, helperText: l.bqNotesHelper),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WasiatiColors.danger)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _save, child: Text(l.commonSave)),
      ],
    );
  }
}
