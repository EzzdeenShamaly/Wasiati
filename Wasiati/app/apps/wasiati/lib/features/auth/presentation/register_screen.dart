import 'address_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../referrals/application/referrals_providers.dart';
import '../../../core/providers.dart';
import '../data/google_sign_in_service.dart';
import 'widgets/auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  // Postal address. Structured, not one free-text line: it decides jurisdiction (which
  // fara'id wording and legal notices the will carries) and it is printed into the executed
  // document, and neither survives "123 Some St, somewhere".
  final _addr1 = TextEditingController();
  final _addr2 = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _postal = TextEditingController();
  /// ISO-3166 alpha-2 of where the user LIVES, which is not the deployment region — someone
  /// served by the US deployment may live in Canada. Prefilled and fully editable (the
  /// picker covers every ISO country). Defaults to Canada, the owner's primary market, on
  /// the North American deployments; the Saudi deployment defaults to Saudi Arabia, since a
  /// KSA sign-up is almost always a Saudi resident.
  String _country = _defaultCountry(Env.region);

  static String _defaultCountry(String region) => switch (region) {
        'KSA' => 'SA',
        _ => 'CA',
      };

  // Region is fixed per regional deployment (data residency) and confirmed later
  // during will creation — never asked at sign-up (spec §5). No region picker.
  final String _region = Env.region;
  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;

  /// From `?ref=CODE` on the share link. It cannot be redeemed yet — /referrals/claim
  /// needs an authenticated user — so it is held until registration succeeds.
  String? _refCode;
  bool _readRefFromUrl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readRefFromUrl) return;
    _readRefFromUrl = true;
    final fromUrl = GoRouterState.of(context).uri.queryParameters['ref']?.trim();
    // A code parked by an earlier visit wins nothing over a fresh link.
    final code = (fromUrl != null && fromUrl.isNotEmpty) ? fromUrl : ref.read(pendingReferralCodeProvider);
    if (code != null && code.isNotEmpty) {
      _refCode = code.toUpperCase();
      // Survive a detour through /login and back.
      Future.microtask(() => ref.read(pendingReferralCodeProvider.notifier).state = _refCode);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _addr1.dispose();
    _addr2.dispose();
    _city.dispose();
    _area.dispose();
    _postal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);

    // Registration signs the user in, which makes the router replace this screen.
    // Capture everything needed for the follow-up claim BEFORE that happens: `ref`
    // and `context` are both unusable once this State is disposed.
    final code = _refCode;
    final referrals = ref.read(referralsApiProvider);
    final pending = ref.read(pendingReferralCodeProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;

    final ok = await runAuthAction(context, () => ref.read(authControllerProvider.notifier).register(
          email: _email.text.trim(),
          password: _password.text,
          region: _region,
          phone: _phone.text.trim(),
          addressLine1: _addr1.text.trim(),
          addressLine2: _addr2.text.trim(),
          addressCity: _city.text.trim(),
          addressArea: _area.text.trim(),
          addressPostalCode: _postal.text.trim(),
          addressCountry: _country,
        ));

    if (ok && code != null && code.isNotEmpty) {
      // A failed claim (self-referral, code already used, already purchased) must
      // never undo a successful registration — the account exists either way.
      try {
        await referrals.claim(code);
        pending.state = null;
        messenger.showSnackBar(SnackBar(content: Text(l.refApplied)));
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: WasiatiColors.danger,
          content: Text(e.message, style: const TextStyle(color: WasiatiColors.onDark)),
        ));
      }
    }

    // The account exists: tell the password manager to save what was just typed. This is
    // the moment a manager offers "Save password?" -- omit it and the credential is never
    // captured, so the next sign-in is typed by hand.
    if (ok) TextInput.finishAutofillContext();

    if (mounted) setState(() => _busy = false);

    // Straight on to proving the phone. Registration signs the user in, so without this the
    // router drops them on the dashboard and the number they just typed is never checked —
    // which is how it came to be required but unverified in the first place. The referral
    // claim above runs first on purpose: it is best-effort and must not delay the step that
    // decides whether we can reach this person at all.
    if (ok && mounted) context.go('/verify-phone');
  }

  /// Signup via Google, carrying the country the picker already holds.
  ///
  /// `_country` is never empty — it is prefilled from the deployment and fully editable —
  /// so the backend derives residency from a STATED country on this path exactly as it does
  /// on the password path. That matters permanently: region is immutable and decides pricing
  /// currency and which KYC rail the user gets, and the alternative input is the build's own
  /// region, which is what filed Saudi residents as US users before.
  Future<void> _google() async {
    setState(() => _googleBusy = true);
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final idToken = await ref.read(googleSignInServiceProvider).idToken();
      await ref.read(authControllerProvider.notifier).loginWithGoogle(
            idToken: idToken,
            addressCountry: _country,
          );
    } on GoogleSignInCancelled {
      // Backing out is normal; say nothing.
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuthScaffold(
      centered: true,
      title: l.authCreateAccount,
      subtitle: l.authRegisterSubtitle,
      children: [
        // METHODS FIRST, then the form.
        //
        // Signup is where the cost of an account is fixed for its whole life: a password
        // account requires an OTP on every single login (auth.service validatePassword),
        // while an OAuth signup is exempt — so the method chosen here decides whether this
        // user ever costs a message. Until now signup offered NO free option at all, which
        // is why every account created so far is on the expensive path.
        //
        // Rendered only when it can actually complete on this platform; the form below is
        // untouched and remains the whole flow when it cannot.
        if (Env.googleSignInAvailable) ...[
          OutlinedButton.icon(
            onPressed: _googleBusy ? null : _google,
            icon: _googleBusy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : WasiatiBrandMark.google(),
            label: Text(l.authContinueGoogle),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Divider(color: context.tokens.hairline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(l.authOr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted)),
            ),
            Expanded(child: Divider(color: context.tokens.hairline)),
          ]),
          const SizedBox(height: 16),
        ],
        // Without an AutofillGroup none of the hints below reach the browser, so a new
        // account could never be offered to the password manager -- the one moment where
        // saving a credential matters most.
        AutofillGroup(
          child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_refCode != null) ...[
                _ReferralChip(code: _refCode!),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: l.authEmail),
                validator: (v) => (v == null || !v.contains('@')) ? l.authInvalidEmail : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                // Required, not optional. This number carries the login second factor, the
                // witness and trustee invitations and the death-claim lookup — a will whose
                // owner left it blank is one whose executors cannot be reached.
                decoration: InputDecoration(labelText: l.authPhone, helperText: l.authPhoneWhy),
                validator: (v) => (v == null || v.trim().length < 6) ? l.authPhoneRequired : null,
              ),
              const SizedBox(height: 14),
              AddressFields(
                country: _country,
                onCountryChanged: (c) => setState(() => _country = c),
                line1: _addr1,
                line2: _addr2,
                city: _city,
                area: _area,
                postal: _postal,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l.authPassword,
                  helperText: l.authPasswordHelper,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.length < 10) ? l.authUseTenChars : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.authCreateAccountButton),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(l.authHaveAccountSignIn),
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }
}

/// Confirms an invite link was recognised, before the user commits to signing up.
class _ReferralChip extends StatelessWidget {
  const _ReferralChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.tokens.gold),
      ),
      child: Row(children: [
        Icon(Icons.card_giftcard_outlined, size: 18, color: context.tokens.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.refCodeChip(code), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(l.refTerms, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ]),
        ),
      ]),
    );
  }
}
