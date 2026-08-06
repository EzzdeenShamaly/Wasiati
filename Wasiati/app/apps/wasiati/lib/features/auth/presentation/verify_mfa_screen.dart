import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/code_cells.dart';
import '../domain/auth_models.dart';
import '../domain/auth_state.dart';
import 'widgets/auth_scaffold.dart';

/// 6-digit MFA (design): six code cells with a gold-focused active cell and a
/// resend countdown, matching the prototype. The subtitle reads the challenge's
/// `via` — the code goes by SMS when the account has a phone, otherwise by
/// email, and the copy must not tell a phoneless user to check their texts.
///
/// The cells and the countdown now live in core/widgets so the claim flow and the
/// heir/trustee portal present the same affordance. Behaviour here is unchanged.
class VerifyMfaScreen extends ConsumerStatefulWidget {
  const VerifyMfaScreen({super.key});
  @override
  ConsumerState<VerifyMfaScreen> createState() => _VerifyMfaScreenState();
}

class _VerifyMfaScreenState extends ConsumerState<VerifyMfaScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _resending = false;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.length < 6) return;
    setState(() => _busy = true);
    await runAuthAction(context, () => ref.read(authControllerProvider.notifier).verifyMfa(_code.text.trim()));
    if (mounted) setState(() => _busy = false);
  }

  /// Asks for a fresh code, and restarts the countdown ONLY if one actually went out.
  ///
  /// [restart] is the countdown's own reset. Calling it unconditionally — which is what
  /// this control used to do, with no API call at all — tells the user a code is coming
  /// when none was sent, and then makes them wait 30s before they can try again. The
  /// failure has to be visible, and the button has to stay available.
  Future<void> _resend(VoidCallback restart) async {
    setState(() => _resending = true);
    // runAuthAction surfaces the error and answers false, so a failed resend leaves the
    // countdown alone and the control usable.
    final sent = await runAuthAction(context, () => ref.read(authControllerProvider.notifier).resendMfa());
    if (!mounted) return;
    setState(() => _resending = false);
    if (sent) {
      restart();
      // The server never names the destination, so this repeats what the prompt already
      // says rather than inventing a masked address it did not give us.
      WasiatiSnack.success(context, context.l10n.mfaResendSent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final via = auth is AuthAwaitingMfa ? auth.via : OtpChannel.sms;
    return AuthScaffold(
      title: l.mfaTitle,
      subtitle: switch (via) {
        OtpChannel.totp => l.mfaSubtitleTotp,
        OtpChannel.email => l.mfaSubtitleEmail,
        OtpChannel.whatsapp => l.mfaSubtitleWhatsapp,
        OtpChannel.sms => l.mfaSubtitleSms,
      },
      centered: true,
      showBack: false,
      // The prototype's MFA card carries no logo seal and no Verify button — entering
      // the sixth digit submits automatically (see CodeCells.onCompleted).
      showSeal: false,
      children: [
        CodeCells(
          controller: _code,
          focusNode: _focus,
          onCompleted: _submit,
          onChanged: () => setState(() {}),
          semanticLabel: l.mfaTitle,
        ),
        // Auto-submits on the sixth digit; this is just the in-flight indicator.
        if (_busy) ...[
          const SizedBox(height: 18),
          const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
        // No resend for an authenticator: nothing was sent, so there is nothing to send
        // again. Offering the control would be a button that can only fail, next to a
        // countdown for a message that does not exist.
        if (!via.isSelfServed) ...[
        const SizedBox(height: 18),
        Center(
          child: ResendCountdown(
            builder: (context, left, restart) => left > 0
                ? Text(context.digits(l.mfaResendWait(left)),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted))
                : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${l.mfaResendReady} ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted)),
                    TextButton(
                      // This used to be `onPressed: restart` — the timer and nothing else.
                      // No code was ever re-issued, so a user whose code was lost or expired
                      // could only start login over, while the button implied otherwise.
                      // The countdown now restarts ONLY after the server confirms a send.
                      onPressed: _resending ? null : () => _resend(restart),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 0)),
                      child: Text(l.mfaResend),
                    ),
                  ]),
          ),
        ),
        ],
      ],
    );
  }
}
