import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/safe_launch.dart';
import '../../../core/providers.dart';
import '../../../core/network/api_exception.dart';
import '../data/google_sign_in_service.dart';
import '../application/passkey_prefs.dart';
import 'passkey_error_text.dart';
import 'widgets/auth_scaffold.dart';

/// Sign-in leads with the methods (design): Google/Apple side by side, a passkey,
/// and — on the KSA build — Nafath as the highlighted (green) primary method, then
/// a gold "Continue with email" link that reveals the email/password form. Email
/// and PASSKEY are the live paths; the SDK-backed social methods degrade to a
/// friendly note until wired. The passkey matters beyond convenience: a password
/// login always requires an OTP (f242634), and a passkey is the one exempt path —
/// it carries its own possession proof.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _passkeyBusy = false;
  bool _googleBusy = false;
  bool _obscure = true;
  bool _emailOpen = false;

  /// Whether THIS device holds a passkey, which decides button order. A passkey is bound to
  /// the device that created it, so "does the account have one" is the wrong question — only
  /// this machine can answer "can I use one here". Unknown until the read lands, and false
  /// is the safe default: the passkey still appears, just not promoted.
  bool _passkeyHere = false;

  @override
  void initState() {
    super.initState();
    ref.read(passkeyPrefsProvider).hasPasskeyOnThisDevice().then((v) {
      if (mounted && v) setState(() => _passkeyHere = true);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await runAuthAction(context, () => ref.read(authControllerProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        ));
    // Tells the password manager the credential was actually USED, which is what makes it
    // offer to save a new one or update a changed one. Without this the fields autofill
    // but nothing is ever learned back.
    if (ok) TextInput.finishAutofillContext();
    if (mounted) setState(() => _busy = false);
  }

  void _soon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.authMethodSoon)));
  }

  /// The real Google sign-in: SDK sheet → id_token → backend verifies → session.
  ///
  /// The client never sends an email or a name; the backend reads them out of the token's
  /// signature, because a client-supplied identity is not an identity. A cancel is silent —
  /// backing out of the sheet is a normal thing to do, not an error worth a red banner.
  Future<void> _google() async {
    setState(() => _googleBusy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final idToken = await ref.read(googleSignInServiceProvider).idToken();
      await ref.read(authControllerProvider.notifier).loginWithGoogle(idToken: idToken);
    } on GoogleSignInCancelled {
      // Nothing to say.
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: WasiatiColors.danger,
          content: Text(
            e is GoogleSignInNoToken ? l.authGoogleMisconfigured : (e is ApiException ? e.message : l.authGoogleFailed),
            style: const TextStyle(color: WasiatiColors.onDark),
          ),
        ));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// The real WebAuthn sign-in: options → browser prompt → verify → session.
  /// On success the router's auth redirect leaves this screen; every failure
  /// mode (no support, cancelled/no passkey here, server refusal) lands as a
  /// specific sentence — never a silent no-op.
  Future<void> _passkey() async {
    setState(() => _passkeyBusy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).loginWithPasskey();
      // Remember that this machine can do it, so next time the passkey is offered FIRST.
      // Recorded on SIGN-IN as well as enrolment because a device may hold a passkey this
      // install never created — a synced iCloud/Google keychain, or a reinstall.
      //
      // NOT awaited: the session already exists and the router is about to leave this
      // screen. Blocking a completed sign-in on a preference write would put a stalled
      // storage channel between the user and their account.
      unawaited(ref.read(passkeyPrefsProvider).markPasskeyOnThisDevice());
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: WasiatiColors.danger,
          content: Text(passkeyErrorMessage(l, e), style: const TextStyle(color: WasiatiColors.onDark)),
        ));
    } finally {
      if (mounted) setState(() => _passkeyBusy = false);
    }
  }

  /// The prototype's "‹ Back" leaves the auth card for the public landing page.
  /// The app has no in-app landing — that lives on the marketing site — so the
  /// link opens wasiati.com (https-only, same pattern as the Settings links).
  Future<void> _backToLanding() async {
    final ok = await safeLaunchExternal('https://wasiati.com');
    if (!ok && mounted) WasiatiSnack.danger(context, context.l10n.settingsLinkError);
  }

  String _regionInfo(AppLocalizations l) {
    switch (Env.region) {
      case 'KSA':
        return '${l.regionSaudiArabia} · SAR';
      case 'CA':
        return '${l.regionCanada} · CAD';
      default:
        return '${l.regionUnitedStates} · USD';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      title: l.authWelcomeBack,
      subtitle: l.authLoginSubtitle,
      centered: true,
      // The prototype's Auth card has a "‹ Back" link beneath it that returns to the
      // public landing page; here that page is the marketing site (see _backToLanding).
      showBack: true,
      onBack: _backToLanding,
      children: [
        // Google + Apple, side by side. Both carry the vendors' real marks:
        // Icons.g_mobiledata was never a Google logo — it is Material's mobile-network
        // indicator (the "G" of 3G/4G) and merely looked close enough to pass review.
        // Google's G keeps its four brand colours (recolouring it breaches their terms);
        // Apple's mark is monochrome by specification and follows the button's ink so it
        // inverts correctly in the night theme.
        // Only the buttons that can actually COMPLETE on this platform are rendered.
        // Google needs its client ids (web id everywhere, plus an iOS id on iOS); Apple
        // needs the Developer Program and an SDK neither of which exists yet, so it keeps
        // the honest "coming soon" rather than a sheet that cannot return. A button that
        // fails is worse than a button that is absent.
        // PASSKEY FIRST for a device that already has one.
        //
        // Otherwise a returning user reaches for the password out of habit and pays for a
        // text on every sign-in, having already done the work of enrolling. The free path
        // has to be the obvious one, and obvious means first — the passkey is also the only
        // login exempt from the OTP.
        if (_passkeyHere) ...[
          _WideOutlined(
            icon: Icons.fingerprint,
            label: l.authUsePasskey,
            busy: _passkeyBusy,
            onTap: (_busy || _passkeyBusy) ? null : _passkey,
          ),
          const SizedBox(height: 10),
        ],
        if (Env.googleSignInAvailable) ...[
          Row(children: [
            Expanded(
              child: _SocialButton(
                mark: WasiatiBrandMark.google(),
                label: l.authContinueGoogle,
                onTap: (_busy || _googleBusy) ? null : _google,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SocialButton(
                mark: WasiatiBrandMark.apple(color: Theme.of(context).colorScheme.onSurface),
                label: l.authContinueApple,
                onTap: _soon,
              ),
            ),
          ]),
          const SizedBox(height: 10),
        ],
        // Passkey — full-width outlined. LIVE (was a _soon stub): runs the real
        // WebAuthn ceremony against /auth/passkeys/login/*.
        //
        // Shown here only when it was NOT already promoted above, so it never appears twice.
        if (!_passkeyHere)
          _WideOutlined(
          icon: Icons.lock_outline,
          label: l.authUsePasskey,
          busy: _passkeyBusy,
          onTap: (_busy || _passkeyBusy) ? null : _passkey,
        ),
        // Nafath — the highlighted (green) primary method, KSA build only.
        if (Env.supportsNafath) ...[
          const SizedBox(height: 10),
          _NafathButton(label: l.authContinueNafath, badge: l.authRecommended, onTap: _soon),
        ],
        const SizedBox(height: 16),
        Divider(color: context.tokens.hairline),
        const SizedBox(height: 8),
        // Email — a gold link that reveals the form.
        if (!_emailOpen)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _emailOpen = true),
              child: Text(l.authContinueEmail),
            ),
          )
        else
          // AutofillGroup, or the autofillHints below do nothing at all: Flutter only
          // registers fields with the platform password manager when they sit in a group.
          // Every hint in this app was already correct and completely inert.
          AutofillGroup(
            child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: l.authEmail),
                  validator: (v) => (v == null || !v.contains('@')) ? l.authInvalidEmail : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l.authPassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? l.authEnterPassword : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.authSignIn),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.go('/forgot-password'),
                    child: Text(l.authForgotPassword),
                  ),
                ),
              ],
            ),
          ),
          ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            l.authDetectedRegion(_regionInfo(l)),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.faint),
          ),
        ),
        // The prototype's Auth block shows no "Create one" link because it assumes you
        // arrive from the landing page's "Start my will" CTA. That leaves a dead end for
        // anyone who opens the app directly, bookmarks /login, or taps Sign in before
        // realising they need an account: no route to /register exists anywhere in auth.
        // Owner-reported as "missing a sign up page" (17 Jul 2026). The string was already
        // authored in both locales for exactly this link — it was simply never wired.
        // Mirrors register_screen's "I already have an account" in the other direction.
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: () => context.go('/register'),
            child: Text(l.authNoAccountCreate),
          ),
        ),
      ],
    );
  }
}

/// A compact social button (Google/Apple) — outlined, centered icon + label.
class _SocialButton extends StatelessWidget {
  /// The vendor's own mark. Takes a widget rather than an [IconData] because these
  /// are brand assets, not our icon set: Google's is four-colour and must not be
  /// tinted, so it cannot be an [Icon].
  final Widget mark;
  final String label;
  /// Nullable so a method that is mid-ceremony renders DISABLED rather than accepting a
  /// second tap — two concurrent sign-in sheets is a state neither SDK recovers from well.
  final VoidCallback? onTap;
  const _SocialButton({required this.mark, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), padding: const EdgeInsets.symmetric(horizontal: 8)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        mark,
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// A full-width outlined method button with a centered icon + label (passkey).
/// A null [onTap] IS the disabled state; [busy] swaps the icon for a spinner
/// while the browser's passkey prompt is up.
class _WideOutlined extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  const _WideOutlined({required this.icon, required this.label, required this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        busy
            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ]),
    );
  }
}

/// Nafath — the highlighted primary method: green filled, shield icon, and a gold
/// RECOMMENDED badge.
class _NafathButton extends StatelessWidget {
  final String label;
  final String badge;
  final VoidCallback onTap;
  const _NafathButton({required this.label, required this.badge, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.verified_user_outlined, size: 18),
        const SizedBox(width: 10),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: WasiatiColors.goldSoft.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(badge,
              style: const TextStyle(
                color: WasiatiColors.goldSoft,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              )),
        ),
      ]),
    );
  }
}
