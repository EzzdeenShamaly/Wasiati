import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/confirm_providers.dart';
import '../presentation/confirm_flow_widgets.dart';

/// `/witness/:id` — the PUBLIC witness-signing flow. Same card, same gates and
/// same accountless visitor as the trustee flow (see trustee_confirm_screen.dart);
/// the DV2.1 prototype designs only the trustee side, so this screen follows
/// that frame with the two extra facts witnessing requires:
///
///  * the LEGAL NAME, typed by the witness, which the backend must match against
///    the name the owner put on the roster (case/diacritic/whitespace-insensitive)
///    before any signature is recorded — spec §6's "national-ID name match"; and
///  * the signature itself, recorded as the same digital acknowledgement the
///    owner's own signing step uses (review_seal_screen.dart:34).
///
/// Enough recorded witness signatures flip the will SIGNED → WITNESSED
/// server-side; without this screen that transition was unreachable in the app.
class WitnessSignScreen extends ConsumerStatefulWidget {
  const WitnessSignScreen({super.key, required this.witnessId});
  final String witnessId;

  @override
  ConsumerState<WitnessSignScreen> createState() => _WitnessSignScreenState();
}

enum _Step { duties, code, done, declined, invalidLink }

class _WitnessSignScreenState extends ConsumerState<WitnessSignScreen> {
  final _legalName = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  _Step _step = _Step.duties;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _legalName.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _nameOk => _legalName.text.trim().length >= 2;

  /// "Continue to sign": sends the SMS code, then opens the code step.
  Future<void> _begin() async {
    if (_busy || !_nameOk) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(confirmApiProvider).sendWitnessCode(widget.witnessId);
      if (mounted) setState(() => _step = _Step.code);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 404) _step = _Step.invalidLink;
        _error = e.statusCode == 404 ? null : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(confirmApiProvider).sendWitnessCode(widget.witnessId);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _sign() async {
    if (_busy || _code.text.length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(confirmApiProvider).confirmWitness(
            widget.witnessId,
            code: _code.text.trim(),
            legalName: _legalName.text.trim(),
          );
      if (mounted) setState(() => _step = _Step.done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 404) {
          _step = _Step.invalidLink;
        } else {
          // Either "Invalid or expired code." or the specific legal-name
          // mismatch explanation — both shown verbatim from the server.
          _error = e.message;
          _code.clear();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return ConfirmCardScaffold(
      children: [
        switch (_step) {
          _Step.duties => Column(children: [
              const ExcludeSemantics(child: Seal(size: 52, status: SealStatus.idle)),
              const SizedBox(height: 14),
              Text(l.wcTitle, textAlign: TextAlign.center, style: t.titleLarge),
              const SizedBox(height: 8),
              Text(l.wcSub,
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.6)),
              const SizedBox(height: 14),
              DutiesBox(text: l.wcDuties),
              const SizedBox(height: 14),
              TextField(
                controller: _legalName,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.name],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _nameOk ? _begin() : null,
                decoration: InputDecoration(
                  labelText: l.wcLegalNameLbl,
                  hintText: l.wcLegalNamePh,
                  helperText: l.wcLegalNameHelp,
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48, // >= 44px target (spec §7)
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_busy || !_nameOk) ? null : _begin,
                  child: _busy
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.wcSignBtn),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: context.tokens.dangerInk)),
              ],
              const SizedBox(height: 4),
              SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _busy ? null : () => setState(() => _step = _Step.declined),
                  style: TextButton.styleFrom(foregroundColor: context.tokens.faint),
                  child: Text(l.tcDecline),
                ),
              ),
            ]),
          _Step.code => ConfirmCodeStep(
              title: l.portalCodeTitle,
              subtitle: l.wcCodeSub,
              controller: _code,
              focusNode: _codeFocus,
              onCompleted: _sign,
              onChanged: () => setState(() {}),
              onResend: _resend,
              busy: _busy,
              error: _error,
            ),
          _Step.done => ConfirmDoneStep(title: l.wcDoneTitle, subtitle: l.wcDoneSub),
          _Step.declined => const ConfirmDeclinedStep(),
          _Step.invalidLink => const ConfirmInvalidLinkStep(),
        },
      ],
    );
  }
}
