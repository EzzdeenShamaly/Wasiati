import 'package:flutter/material.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/code_cells.dart';

/// Shared furniture for the trustee-confirmation and witness-signing flows,
/// transcribed from the DV2.1 prototype's "Trustee confirmation" frame
/// (Wasiati Prototype.dc.html:1643-1668): a single centred card, max 400 wide,
/// r18, 28×26 padding, everything centred, with the step as state — never as a
/// URL, since the only thing these pages may put in the address bar is the
/// roster id that arrived by SMS.
class ConfirmCardScaffold extends StatelessWidget {
  const ConfirmCardScaffold({super.key, required this.children, this.footnote});
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
                  decoration: BoxDecoration(
                    color: tokens.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: tokens.hairline),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 14),
                  Text(footnote!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.faint)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The duties panel — the prototype's bordered start-aligned explainer box.
class DutiesBox extends StatelessWidget {
  const DutiesBox({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: tokens.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6)),
    );
  }
}

/// The code step: title, sub, the shared six cells, the error line and the
/// shared resend countdown. Both flows show exactly this; only what happens on
/// the sixth digit differs.
class ConfirmCodeStep extends StatelessWidget {
  const ConfirmCodeStep({
    super.key,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    required this.onChanged,
    required this.onResend,
    required this.busy,
    this.error,
  });

  final String title;
  final String subtitle;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCompleted;
  final VoidCallback onChanged;
  final Future<void> Function() onResend;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 8),
      Text(subtitle,
          textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.6)),
      const SizedBox(height: 18),
      CodeCells(
        controller: controller,
        focusNode: focusNode,
        onCompleted: onCompleted,
        onChanged: onChanged,
        semanticLabel: title,
      ),
      if (error != null) ...[
        const SizedBox(height: 14),
        Text(error!, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: tokens.dangerInk)),
      ],
      if (busy) ...[
        const SizedBox(height: 18),
        const Center(
            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ],
      const SizedBox(height: 16),
      Center(
        child: ResendCountdown(
          builder: (context, left, restart) => left > 0
              // A duration is a computed number, so it reads in the locale's own
              // digits. The CODE itself never does — see CodeCells.
              ? Text(context.digits(l.portalCodeResendWait(left)),
                  style: t.bodySmall?.copyWith(color: tokens.muted))
              : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${l.portalCodeResendReady} ', style: t.bodySmall?.copyWith(color: tokens.muted)),
                  TextButton(
                    onPressed: () async {
                      await onResend();
                      restart();
                    },
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 0)),
                    child: Text(l.portalCodeResend),
                  ),
                ]),
        ),
      ),
    ]);
  }
}

/// The confirmed step — the witnessed-state seal over a title and supporting
/// line, closing with the "you can close this page" note (the prototype's
/// "Back" button leads to a will detail an accountless visitor does not have).
class ConfirmDoneStep extends StatelessWidget {
  const ConfirmDoneStep({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      // Decorative — the title carries the meaning for a screen reader.
      const ExcludeSemantics(child: Seal(size: 58, status: SealStatus.witnessed, filled: true)),
      const SizedBox(height: 14),
      Text(title, textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 8),
      Text(subtitle,
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.6)),
      const SizedBox(height: 14),
      Text(l.confirmClosePage,
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: context.tokens.faint)),
    ]);
  }
}

/// Declined: nothing recorded, nothing sent — say exactly that.
class ConfirmDeclinedStep extends StatelessWidget {
  const ConfirmDeclinedStep({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      const ExcludeSemantics(child: Seal(size: 52, status: SealStatus.idle)),
      const SizedBox(height: 14),
      Text(l.confirmDeclinedTitle, textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 8),
      Text(l.confirmDeclinedSub,
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.6)),
    ]);
  }
}

/// A dead roster id (404). One state for wrong, revoked and mistyped alike —
/// the endpoint does not distinguish, so neither may the copy.
class ConfirmInvalidLinkStep extends StatelessWidget {
  const ConfirmInvalidLinkStep({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Column(children: [
      ExcludeSemantics(child: Icon(Icons.link_off, size: 32, color: context.tokens.muted)),
      const SizedBox(height: 14),
      Text(l.confirmLinkInvalidTitle, textAlign: TextAlign.center, style: t.titleLarge),
      const SizedBox(height: 8),
      Text(l.confirmLinkInvalidSub,
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.6)),
    ]);
  }
}
