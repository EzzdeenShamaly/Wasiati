import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/confirm_providers.dart';
import '../presentation/confirm_flow_widgets.dart';

/// `/trustee/:id` — the PUBLIC trustee-confirmation flow, transcribed from the
/// DV2.1 prototype (Wasiati Prototype.dc.html:1643-1668): duties → "Accept the
/// role" → 6-digit SMS code → confirmed, under the witnessed-state seal.
///
/// The visitor is the trustee named on someone ELSE's will, arriving from an
/// SMS with no Wasiati account — so this route must survive BOTH router gates
/// (signed-out and cold-load; see app_router.dart). Until this screen existed
/// the app could send a trustee their code but offered nowhere to type it, so
/// no trustee could ever reach CONFIRMED and no release gate could be satisfied.
///
/// The prototype personalises the copy with the owner's name; there is no
/// public read endpoint for a trustee row (deliberately — the id arrives in an
/// SMS and must not become an oracle), so the copy here stays generic.
class TrusteeConfirmScreen extends ConsumerStatefulWidget {
  const TrusteeConfirmScreen({super.key, required this.trusteeId});
  final String trusteeId;

  @override
  ConsumerState<TrusteeConfirmScreen> createState() => _TrusteeConfirmScreenState();
}

enum _Step { duties, code, done, declined, invalidLink }

class _TrusteeConfirmScreenState extends ConsumerState<TrusteeConfirmScreen> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  _Step _step = _Step.duties;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// "Accept the role": sends the SMS code, then opens the code step. A 404
  /// means the id in the link matches no trustee — the one terminal state.
  Future<void> _accept() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(confirmApiProvider).sendTrusteeCode(widget.trusteeId);
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
      await ref.read(confirmApiProvider).sendTrusteeCode(widget.trusteeId);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _code.text.length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(confirmApiProvider).confirmTrustee(widget.trusteeId, code: _code.text.trim());
      if (mounted) setState(() => _step = _Step.done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 404) {
          _step = _Step.invalidLink;
        } else {
          // "Invalid or expired code." — shown verbatim; the backend does not
          // distinguish and neither may we.
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
              // Decorative — the title beneath carries the meaning.
              const ExcludeSemantics(child: Seal(size: 52, status: SealStatus.idle)),
              const SizedBox(height: 14),
              Text(l.tcTitle, textAlign: TextAlign.center, style: t.titleLarge),
              const SizedBox(height: 8),
              Text(l.tcSub,
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.6)),
              const SizedBox(height: 14),
              DutiesBox(text: l.tcDuties),
              const SizedBox(height: 14),
              SizedBox(
                height: 48, // >= 44px target (spec §7)
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: _busy
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.tcAcceptBtn),
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
              subtitle: l.tcCodeSub,
              controller: _code,
              focusNode: _codeFocus,
              onCompleted: _confirm,
              onChanged: () => setState(() {}),
              onResend: _resend,
              busy: _busy,
              error: _error,
            ),
          _Step.done => ConfirmDoneStep(title: l.tcDoneTitle, subtitle: l.tcDoneSub),
          _Step.declined => const ConfirmDeclinedStep(),
          _Step.invalidLink => const ConfirmInvalidLinkStep(),
        },
      ],
    );
  }
}
