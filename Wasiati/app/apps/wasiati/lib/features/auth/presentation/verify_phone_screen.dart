import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/code_cells.dart';
import '../application/passkey_prefs.dart';
import 'widgets/auth_scaffold.dart';

/// Signup step 2: prove the phone given on step 1.
///
/// The number was required at signup but nothing proved it, so a typo sat on the account
/// looking exactly like a good number. That is worse than a wrong email, because this number
/// carries the login second factor, the witness and trustee invitations, and the death-claim
/// lookup — the mistake stays silent until the will is being executed and the people who have
/// to act cannot be reached.
///
/// Not skippable. Everything the account can do later depends on this number reaching a
/// handset the owner holds, and it is far cheaper to find out now than at execution.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key});
  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _resending = false;
  bool _sending = true;

  @override
  void initState() {
    super.initState();
    // Send on arrival: the owner has just been told a code is coming, so making them press
    // a button for it first would be asking them to request something already promised.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendInitial());
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _sendInitial() async {
    final ok = await runAuthAction(context, () => ref.read(authApiProvider).sendPhoneCode());
    if (!mounted) return;
    setState(() => _sending = false);
    // A failed first send leaves Resend available rather than stranding the screen — the
    // 30s cooldown and hourly cap mean "try again shortly" is a real answer.
    if (!ok) return;
  }

  Future<void> _submit() async {
    if (_code.text.length < 6) return;
    setState(() => _busy = true);
    final ok = await runAuthAction(
      context,
      () => ref.read(authApiProvider).verifyPhone(_code.text.trim()),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // Clear on a bad code so the next attempt starts from an empty field rather than
      // making the owner delete six digits by hand.
      _code.clear();
      _focus.requestFocus();
      return;
    }
    // Offer a passkey before handing over the dashboard — once, and only if we have not
    // already asked. This is the moment it converts: the account is minutes old and the
    // owner is still in a setup frame of mind. Every enrolment here removes that user from
    // the login-OTP bill for good, because a passkey is the one exempt sign-in path.
    //
    // A failed preference read means "not prompted", which costs at most one extra offer —
    // never a blocked signup.
    final prompted = await ref.read(passkeyPrefsProvider).hasBeenPrompted();
    if (mounted) context.go(prompted ? '/dashboard' : '/passkey-setup');
  }

  /// Asks for a fresh code, restarting the countdown ONLY if one actually went out.
  ///
  /// Restarting it unconditionally tells the owner a code is coming when none was sent, and
  /// then makes them wait 30s before they can try again. The server 429s on the cooldown and
  /// on the hourly cap, and that has to stay visible.
  Future<void> _resend(VoidCallback restart) async {
    setState(() => _resending = true);
    final sent = await runAuthAction(context, () => ref.read(authApiProvider).sendPhoneCode());
    if (!mounted) return;
    setState(() => _resending = false);
    if (sent) {
      restart();
      WasiatiSnack.success(context, context.l10n.authPhoneCodeResent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      centered: true,
      title: l.authVerifyPhoneTitle,
      subtitle: l.authVerifyPhoneSubtitle,
      children: [
        if (_sending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          CodeCells(
            controller: _code,
            focusNode: _focus,
            // The sixth digit submits, so the owner never hunts for a button.
            onCompleted: _submit,
            onChanged: () => setState(() {}),
            semanticLabel: l.authVerifyPhoneTitle,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.authVerifyPhoneCta),
          ),
          const SizedBox(height: 12),
          ResendCountdown(
            builder: (context, seconds, restart) => TextButton(
              onPressed: (seconds > 0 || _resending) ? null : () => _resend(restart),
              child: Text(seconds > 0 ? context.digits(l.mfaResendWait(seconds)) : l.mfaResend),
            ),
          ),
        ],
      ],
    );
  }
}
