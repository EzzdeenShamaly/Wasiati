import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/code_cells.dart';
import 'widgets/auth_scaffold.dart';

/// Password reset by one-time code: email -> 6-digit code -> new password.
///
/// The code goes to the account's phone when there is one, otherwise its email.
/// The app cannot know which: the backend deliberately answers `{sent: true}`
/// either way, so an anonymous caller can't learn whether an address is
/// registered or has a phone on file. The copy therefore states the rule, never
/// this account's facts. Failures at the final step are equally opaque by
/// design — wrong, expired and burned codes, unknown addresses and OAuth-only
/// accounts all get one message, and the UI must not pretend to distinguish.
///
/// The emailed reset LINK still works server-side for mail already in inboxes
/// (/reset-password?token=...), but the app leads with the code flow.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, code, password }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  var _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_email.text.contains('@')) return;
    setState(() => _busy = true);
    final ok = await runAuthAction(
        context, () => ref.read(authApiProvider).forgotPasswordCode(_email.text.trim()));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _step = _Step.code;
    });
  }

  /// Resend from the code step; the countdown restarts only if the call landed.
  Future<void> _resend(VoidCallback restart) async {
    final ok = await runAuthAction(
        context, () => ref.read(authApiProvider).forgotPasswordCode(_email.text.trim()));
    if (mounted && ok) restart();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final ok = await runAuthAction(
      context,
      () => ref.read(authApiProvider).resetPasswordWithCode(
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: _password.text,
          ),
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _busy = false);
      // The password changed: let the manager save the new one so the next sign-in fills.
      TextInput.finishAutofillContext();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.resetSuccess)));
      context.go('/login');
    } else {
      // One indistinguishable failure by design; the snackbar already carries the
      // backend's single message. Clear the cells and let them try a fresh code.
      setState(() {
        _busy = false;
        _code.clear();
        _step = _Step.code;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return switch (_step) {
      _Step.email => AuthScaffold(
          centered: true,
          title: l.forgotTitle,
          subtitle: l.forgotSubtitle,
          children: [
            // A group even for one field: without it the hint is inert (see code_cells),
            // and this is where the manager should offer the account's known email.
            AutofillGroup(
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                decoration: InputDecoration(labelText: l.authEmail),
                onSubmitted: (_) => _sendCode(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy ? null : _sendCode,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.forgotSendCode),
            ),
          ],
        ),
      _Step.code => AuthScaffold(
          centered: true,
          title: l.mfaTitle,
          subtitle: l.forgotCodeSentBody(_email.text.trim()),
          children: [
            CodeCells(
              controller: _code,
              focusNode: _codeFocus,
              // The code is only checked server-side together with the new
              // password, so the sixth digit advances rather than submits.
              onCompleted: () => setState(() => _step = _Step.password),
              onChanged: () => setState(() {}),
              semanticLabel: l.mfaTitle,
            ),
            const SizedBox(height: 18),
            Center(
              child: ResendCountdown(
                builder: (context, left, restart) => left > 0
                    ? Text(context.digits(l.mfaResendWait(left)),
                        style: text.bodySmall?.copyWith(color: context.tokens.muted))
                    : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('${l.mfaResendReady} ',
                            style: text.bodySmall?.copyWith(color: context.tokens.muted)),
                        TextButton(
                          onPressed: () => _resend(restart),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: const Size(0, 0)),
                          child: Text(l.mfaResend),
                        ),
                      ]),
              ),
            ),
          ],
        ),
      _Step.password => AuthScaffold(
          centered: true,
          title: l.resetTitle,
          children: [
            AutofillGroup(
              child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: l.resetNewPasswordLabel,
                    helperText: l.resetHelper,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 10) ? l.resetValidator : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.resetSubmit),
                ),
              ]),
            ),
            ),
          ],
        ),
    };
  }
}
