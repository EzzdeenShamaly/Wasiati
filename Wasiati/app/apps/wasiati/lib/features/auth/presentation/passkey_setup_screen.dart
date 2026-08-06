import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../application/passkey_prefs.dart';
import 'passkey_error_text.dart';
import 'widgets/auth_scaffold.dart';

/// Offered once, immediately after signup: add a passkey so future sign-ins need no code.
///
/// This is the last rung of the MFA ladder and the one that decides whether the rest of it
/// pays. MFA is mandatory on every password login, and a passkey is the ONE exempt path
/// (auth.service validatePassword) — so a user who enrols here stops costing a message per
/// sign-in, permanently, and gains a phishing-resistant credential in the bargain.
///
/// The enrolment itself has worked in Settings > Security all along. Nobody goes looking
/// for it there. This asks at the one moment people say yes: they have just committed to
/// the product and are still in a setup frame of mind.
///
/// Skipping is FREE and remembered. A security prompt that reappears every visit teaches
/// people to dismiss security prompts without reading them, which costs more than the
/// passkey saves.
class PasskeySetupScreen extends ConsumerStatefulWidget {
  const PasskeySetupScreen({super.key});
  @override
  ConsumerState<PasskeySetupScreen> createState() => _PasskeySetupScreenState();
}

class _PasskeySetupScreenState extends ConsumerState<PasskeySetupScreen> {
  bool _busy = false;

  Future<void> _leave() async {
    // Marked on the way out either way: offered is offered. Otherwise a user who declined
    // would be asked again on their next signup-adjacent navigation.
    await ref.read(passkeyPrefsProvider).markPrompted();
    if (mounted) context.go('/dashboard');
  }

  Future<void> _setUp() async {
    setState(() => _busy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(passkeyServiceProvider).register();
      await ref.read(passkeyPrefsProvider).markPasskeyOnThisDevice();
      if (!mounted) return;
      WasiatiSnack.success(context, l.passkeyAdded);
      await _leave();
    } catch (e) {
      // A failure here must not block the account. Unsupported browser, a dismissed OS
      // prompt, no platform authenticator — all are ordinary, and none of them mean the
      // user cannot use the product. Say what happened and leave both buttons alive.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: WasiatiColors.danger,
          content: Text(passkeyErrorMessage(l, e, registering: true),
              style: const TextStyle(color: WasiatiColors.onDark)),
        ));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return AuthScaffold(
      centered: true,
      title: l.pkSetupTitle,
      subtitle: l.pkSetupBlurb,
      // No back arrow: there is nothing behind this — the account already exists and the
      // phone is already verified. Forward or skip, and skip is one tap.
      showBack: false,
      children: [
        Center(
          child: Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(color: context.tokens.highlight, shape: BoxShape.circle),
            child: Icon(Icons.fingerprint, size: 32, color: context.tokens.gold),
          ),
        ),
        const SizedBox(height: 22),
        // The concrete promise, not a security lecture: no code to wait for.
        Text(l.pkSetupWhy, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _busy ? null : _setUp,
          icon: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.fingerprint, size: 19),
          label: Text(l.pkSetupCta),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _leave,
            child: Text(l.pkSetupSkip),
          ),
        ),
        const SizedBox(height: 4),
        // Says plainly that nothing is lost by skipping, and that the password still works.
        Text(l.pkSetupLater, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
      ],
    );
  }
}
