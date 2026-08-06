import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../domain/auth_state.dart';
import 'widgets/auth_scaffold.dart';

/// Reached from the emailed link: /verify-email?token=... Auto-verifies the token.
/// With no token it offers to resend to the signed-in (or entered) address.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Future<void>? _verifyFuture;
  final _email = TextEditingController();
  bool _resending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    final auth = ref.read(authControllerProvider);
    final email = auth is AuthSignedIn ? auth.user.email : _email.text.trim();
    if (!email.contains('@')) return;
    setState(() => _resending = true);
    await runAuthAction(context, () => ref.read(authApiProvider).resendVerification(email));
    if (mounted) {
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.verifyEmailSent)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final token = GoRouterState.of(context).uri.queryParameters['token'];
    final text = Theme.of(context).textTheme;
    final signedIn = ref.watch(authControllerProvider) is AuthSignedIn;

    if (token != null && token.isNotEmpty) {
      _verifyFuture ??= ref.read(authApiProvider).verifyEmail(token);
      return AuthScaffold(
      centered: true,
        title: l.verifyEmailVerifyingTitle,
        children: [
          FutureBuilder<void>(
            future: _verifyFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(l.verifyEmailInvalid, style: text.bodyLarge),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: _resending ? null : _resend, child: Text(l.verifyEmailResend)),
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Seal(size: 40, status: SealStatus.verified),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.verifyEmailVerified, style: text.titleMedium)),
                ]),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go(signedIn ? '/dashboard' : '/login'),
                  child: Text(signedIn ? l.verifyEmailContinue : l.verifyEmailSignIn),
                ),
              ]);
            },
          ),
        ],
      );
    }

    // No token — resend flow.
    return AuthScaffold(
      centered: true,
      title: l.verifyEmailTitle,
      subtitle: l.verifyEmailSubtitle,
      children: [
        if (!signedIn) ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l.authEmail),
          ),
          const SizedBox(height: 16),
        ],
        ElevatedButton(
          onPressed: _resending ? null : _resend,
          child: _resending
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.verifyEmailResend),
        ),
      ],
    );
  }
}
