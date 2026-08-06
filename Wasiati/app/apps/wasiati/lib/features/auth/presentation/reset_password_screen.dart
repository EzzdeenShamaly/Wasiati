import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import 'widgets/auth_scaffold.dart';

/// Reached from the emailed link: /reset-password?token=...
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(String token) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAuthAction(
      context,
      () => ref.read(authApiProvider).resetPassword(token: token, newPassword: _password.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Let the password manager save the new password for the next sign-in.
      TextInput.finishAutofillContext();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.resetSuccess)),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final token = GoRouterState.of(context).uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      return AuthScaffold(
      centered: true,
        title: l.resetInvalidTitle,
        subtitle: l.resetInvalidSubtitle,
        children: [ElevatedButton(onPressed: () => context.go('/forgot-password'), child: Text(l.resetRequestNew))],
      );
    }
    return AuthScaffold(
      centered: true,
      title: l.resetTitle,
      children: [
        AutofillGroup(
          child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l.resetNewPasswordLabel,
                  helperText: l.resetHelper,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 10) ? l.resetValidator : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : () => _submit(token),
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.resetSubmit),
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }
}
