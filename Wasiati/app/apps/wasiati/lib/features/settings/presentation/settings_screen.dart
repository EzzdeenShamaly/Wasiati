import 'package:flutter/material.dart';
// Clipboard: backup codes are shown once, so "Copy all" is the primary way they are saved.
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/locale/locale_provider.dart';
import '../../../core/providers.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/presentation/passkey_error_text.dart';
import '../../checkin/application/checkin_providers.dart';
import '../../checkin/data/checkin_api.dart';
import '../application/security_prefs_provider.dart';

/// The legal pages live on the marketing site in BOTH languages
/// (landing/public/{privacy,terms}.html and the /ar/ equivalents); an Arabic UI
/// must land on the Arabic text, not on English with an "العربية" link.
///
/// Top-level (not a private method) so legal_links_resolve_test.dart can pin
/// every URL this can produce to a page that actually exists in the repo —
/// these links were dead in both directions once already.
String legalUrl(String languageCode, String page) =>
    'https://wasiati.com${languageCode == 'ar' ? '/ar' : ''}/$page';

/// Settings (design 9c). Only genuinely-wired controls are surfaced: appearance
/// (real theme mode), a password-reset trigger, sign out, and legal links. We
/// avoid toggles with no backing so nothing here is a lie.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  ({String flag, String currency}) _regionMeta(String r) => switch (r) {
        'KSA' => (flag: '🇸🇦', currency: 'SAR'),
        'CA' => (flag: '🇨🇦', currency: 'CAD'),
        _ => (flag: '🇺🇸', currency: 'USD'),
      };

  String _regionName(AppLocalizations l, String r) => switch (r) {
        'KSA' => l.regionSaudiArabia,
        'CA' => l.regionCanada,
        _ => l.regionUnitedStates,
      };

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) WasiatiSnack.danger(context, context.l10n.settingsLinkError);
  }

  String _legalUrl(BuildContext context, String page) =>
      legalUrl(Localizations.localeOf(context).languageCode, page);

  Future<void> _resetPassword(BuildContext context, WidgetRef ref, String email) async {
    try {
      await ref.read(authApiProvider).forgotPassword(email);
      if (context.mounted) WasiatiSnack.success(context, context.l10n.settingsResetSent(email));
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.user : null;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final security = ref.watch(securityPrefsProvider);
    final meta = _regionMeta(user?.region ?? 'US');
    final regionName = _regionName(l, user?.region ?? 'US');

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          return SingleChildScrollView(
            // The bar's height rides on the content, so the settings cards slide under
            // the glass mid-scroll and the wordmark still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(l.settingsTitle, style: t.headlineSmall),
                  const SizedBox(height: 16),

                  // Profile
                  _Card(
                    child: Row(children: [
                      const Seal(size: 44, status: SealStatus.verified),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(user?.email ?? '—', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Wrap(spacing: 8, children: [
                            WasiatiChip('${meta.flag} $regionName', kind: WasiatiChipKind.region),
                            if (user?.role == 'ADMIN') WasiatiChip(l.settingsRoleAdmin, kind: WasiatiChipKind.admin),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Appearance — the prototype's two rows (data-screen-label
                  // "Settings"): an explicit dark-mode switch over "match system",
                  // which is the app's default and the state a fresh install is in.
                  _Section(title: l.settingsAppearance),
                  _Card(
                    padded: false,
                    child: Column(children: [
                      const _ThemeRow(),
                      _divider(context),
                      _ToggleRow(
                        icon: Icons.brightness_auto_outlined,
                        label: l.settingsThemeMatchSystem,
                        value: themeMode == ThemeMode.system,
                        // Leaving "match system" has to land on a concrete mode, and
                        // the honest one is whatever the device is showing right now —
                        // so the switch flips without the page changing colour.
                        onChanged: (on) => ref.read(themeModeProvider.notifier).set(on
                            ? ThemeMode.system
                            : (MediaQuery.platformBrightnessOf(context) == Brightness.dark
                                ? ThemeMode.dark
                                : ThemeMode.light)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Region & language
                  _Section(title: l.settingsRegionLanguage),
                  _Card(
                    child: Column(children: [
                      _InfoRow(icon: Icons.public, label: l.settingsRegion, value: '$regionName · ${meta.currency}'),
                      _divider(context),
                      _rowLabel(context, l.settingsLanguage, l.settingsLanguageSystem),
                      const SizedBox(height: 12),
                      _LanguageToggle(
                        locale: locale,
                        onChanged: (loc) => ref.read(localeProvider.notifier).set(loc),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(l.settingsRegionNote, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
                  ),
                  const SizedBox(height: 16),

                  // Security
                  _Section(title: l.settingsSecurity),
                  _Card(
                    padded: false,
                    child: Column(children: [
                      // Device-local biometric unlock (prototype Security section).
                      _ToggleRow(
                        icon: Icons.face_outlined,
                        label: l.settingsFaceApp,
                        value: security.faceUnlockApp,
                        onChanged: (_) => ref.read(securityPrefsProvider.notifier).toggleFaceApp(),
                      ),
                      _divider(context),
                      _ToggleRow(
                        icon: Icons.lock_outline,
                        label: l.settingsFaceVault,
                        value: security.faceUnlockVault,
                        onChanged: (_) => ref.read(securityPrefsProvider.notifier).toggleFaceVault(),
                      ),
                      _divider(context),
                      // Passkey registration — the supply side of passkey sign-in:
                      // the login screen's passkey button has nothing to use until
                      // a signed-in user has been HERE.
                      const _PasskeyRow(),
                      _divider(context),
                      // The free second factor. Sits beside passkeys on purpose: both let
                      // an account stop paying for a text message on every sign-in.
                      const _TotpRow(),
                      _divider(context),
                      // Directly under the authenticator, because it is what makes relying
                      // on one safe: an app lives on a single device, and this is the way
                      // back in when that device is gone.
                      const _RecoveryCodesRow(),
                      _divider(context),
                      _ActionRow(
                        icon: Icons.password_outlined,
                        label: l.settingsChangePassword,
                        sub: l.settingsChangePasswordSub,
                        onTap: user == null ? null : () => _resetPassword(context, ref, user.email),
                      ),
                      _divider(context),
                      _ActionRow(
                        icon: Icons.verified_user_outlined,
                        label: l.settingsIdentity,
                        sub: l.settingsIdentitySub,
                        onTap: () => context.go('/kyc'),
                      ),
                      _divider(context),
                      _ActionRow(
                        icon: Icons.logout,
                        label: l.commonSignOut,
                        sub: l.settingsSignOutSub,
                        signOut: true,
                        onTap: () => ref.read(authControllerProvider.notifier).logout(),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Billing (spec §2) — plan + renewal, card, invoices, cancel.
                  _Section(title: l.billingTitle),
                  _Card(
                    padded: false,
                    child: Column(children: [
                      _ActionRow(
                        icon: Icons.receipt_long_outlined,
                        label: l.prManageBilling,
                        sub: l.prBillingSub,
                        onTap: () => context.go('/billing'),
                      ),
                      _divider(context),
                      // Account credit lives on /referrals; without a row here (and
                      // the dashboard rail's link) that screen was registered but
                      // unreachable.
                      _ActionRow(
                        icon: Icons.card_giftcard_outlined,
                        label: l.settingsReferrals,
                        sub: l.settingsReferralsSub,
                        onTap: () => context.go('/referrals'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Inactivity check-in + who may report my death (spec §6).
                  _Section(title: l.checkinTitle),
                  const _CheckinCard(),
                  const SizedBox(height: 16),

                  // Legal
                  _Section(title: l.settingsLegal),
                  _Card(
                    padded: false,
                    child: Column(children: [
                      _ActionRow(icon: Icons.shield_outlined, label: l.settingsPrivacy, external: true, onTap: () => _open(context, _legalUrl(context, 'privacy'))),
                      _divider(context),
                      _ActionRow(icon: Icons.gavel_outlined, label: l.settingsTerms, external: true, onTap: () => _open(context, _legalUrl(context, 'terms'))),
                      _divider(context),
                      _ActionRow(icon: Icons.support_agent_outlined, label: l.settingsContact, external: true, onTap: () => _open(context, 'mailto:support@wasiati.com')),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Danger
                  _Card(
                    tinted: true,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.settingsDeleteTitle, style: t.titleSmall?.copyWith(color: context.tokens.dangerInk, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(l.settingsDeleteBody, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: WasiatiButtons.destructive(context),
                        onPressed: () => _open(context, 'mailto:privacy@wasiati.com?subject=Account%20deletion%20request'),
                        child: Text(l.settingsRequestDeletion),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text('Wasiati · وصيتي', style: t.bodySmall?.copyWith(color: context.tokens.faint, letterSpacing: 0.4)),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _rowLabel(BuildContext context, String label, String sub) {
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text(sub, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
      ]),
    );
  }

  Widget _divider(BuildContext context) => Divider(height: 1, color: context.tokens.hairline);
}

/// The "Dark mode" row: the same prototype theme pill the rail and the auth
/// screens use, so the app has exactly one theme control rather than three.
///
/// The pill tracks the *rendered* brightness, not the mode — under "match system"
/// there is no stored light/dark to show, and reading the theme means the switch
/// always agrees with the page around it. Tapping it commits to an explicit mode
/// (and so turns "match system" off), which is what the prototype does too.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 6, 12, 6),
      child: Row(children: [
        Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 20, color: context.tokens.muted),
        const SizedBox(width: 16),
        Expanded(
          child: Text(context.l10n.settingsThemeDarkMode, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        WasiatiThemePill(
          dark: dark,
          semanticLabel: context.l10n.settingsThemeDarkMode,
          onTap: () => ref.read(themeModeProvider.notifier).toggle(MediaQuery.platformBrightnessOf(context)),
        ),
      ]),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  final Locale? locale;
  final ValueChanged<Locale?> onChanged;
  const _LanguageToggle({required this.locale, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final options = <(Locale?, String, IconData)>[
      (null, l.settingsLanguageSystem, Icons.devices_outlined),
      (const Locale('en'), l.settingsLanguageEnglish, Icons.abc),
      (const Locale('ar'), l.settingsLanguageArabic, Icons.language_outlined),
    ];
    return Row(children: [
      for (var i = 0; i < options.length; i++) ...[
        Expanded(
          child: _SegTab(
            selected: locale?.languageCode == options[i].$1?.languageCode,
            icon: options[i].$3,
            label: options[i].$2,
            onTap: () => onChanged(options[i].$1),
          ),
        ),
        if (i != options.length - 1) const SizedBox(width: 8),
      ],
    ]);
  }
}

class _SegTab extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SegTab({required this.selected, required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? WasiatiColors.bottleGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? WasiatiColors.bottleGreen : context.tokens.hairline),
        ),
        child: Column(children: [
          Icon(icon, size: 19, color: selected ? WasiatiColors.onDark : context.tokens.muted),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? WasiatiColors.onDark : context.tokens.muted)),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: context.tokens.muted),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: t.bodyMedium)),
        Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool external;
  final bool signOut;
  final VoidCallback? onTap;
  const _ActionRow({required this.icon, required this.label, this.sub, this.external = false, this.signOut = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // The row's icon and label both take this, so it is type, not a fill: the raw
    // danger read 2.28:1 on the night card (the reported "Sign out" bug).
    final color = signOut ? context.tokens.dangerInk : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? context.tokens.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: color)),
              if (sub != null) Text(sub!, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ]),
          ),
          external
              ? Icon(Icons.open_in_new, size: 18, color: context.tokens.faint)
              : WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 18, color: context.tokens.faint),
        ]),
      ),
    );
  }
}

/// A settings row with a trailing switch (biometric prefs). Mirrors [_ActionRow]'s
/// icon + label layout; uses [SwitchListTile] so it tracks the app's switch theme.
class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.icon, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      secondary: Icon(icon, size: 20, color: context.tokens.muted),
      value: value,
      onChanged: onChanged,
      title: Text(label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

/// "Add a passkey" (Security) — registers a WebAuthn credential for the
/// signed-in user via /auth/passkeys/register/*, run by PasskeyService.
///
/// This row is what makes passkey SIGN-IN exist at all: without a place that
/// creates one, the login button is decoration. It also carries the security
/// posture: a password login always requires an OTP (f242634); a passkey is
/// the one exempt path, so this is how a frequent user opts into the fast lane.
/// Every outcome is voiced — added, cancelled, already registered, unsupported
/// browser — never a silent no-op.
class _PasskeyRow extends ConsumerStatefulWidget {
  const _PasskeyRow();
  @override
  ConsumerState<_PasskeyRow> createState() => _PasskeyRowState();
}

class _PasskeyRowState extends ConsumerState<_PasskeyRow> {
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    final l = context.l10n;
    try {
      await ref.read(passkeyServiceProvider).register();
      if (mounted) WasiatiSnack.success(context, l.passkeyAdded);
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, passkeyErrorMessage(l, e, registering: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _ActionRow(
      icon: Icons.fingerprint,
      label: l.settingsAddPasskey,
      sub: l.settingsAddPasskeySub,
      onTap: _busy ? null : _add,
    );
  }
}

/// Enrol (or drop) an authenticator app — the free second factor.
///
/// This is the supply side of the TOTP login path, exactly as [_PasskeyRow] is for
/// passkeys: the backend accepts an authenticator code at sign-in, but nothing could
/// enrol one, so the capability existed and no user could reach it.
///
/// Worth stating plainly in the UI because it is true: enrolling is free, works with no
/// signal, and is safer than a text — SMS is SIM-swap vulnerable and NIST SP 800-63B
/// treats it as a restricted authenticator. It also removes this account from the SMS
/// bill permanently, which at Saudi rates is the product's largest per-login cost.
class _TotpRow extends ConsumerStatefulWidget {
  const _TotpRow();
  @override
  ConsumerState<_TotpRow> createState() => _TotpRowState();
}

class _TotpRowState extends ConsumerState<_TotpRow> {
  bool _busy = false;
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final on = await ref.read(authApiProvider).totpEnabled();
      if (mounted) setState(() => _enabled = on);
    } catch (_) {
      // Unknown rather than wrong: the row simply offers "Set up" and the server is the
      // one that decides. Failing the whole settings screen over this would be worse.
      if (mounted) setState(() => _enabled = null);
    }
  }

  Future<void> _setUp() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final started = await ref.read(authApiProvider).totpStart();
      if (!mounted) return;
      final code = await _askForCode(
        title: l.secTotpTitle,
        blurb: l.secTotpScan,
        // The secret is shown so it can be typed into an app on another device. No QR
        // renderer is bundled, and a key you can copy beats a QR you cannot scan.
        secret: started.secret,
      );
      if (code == null || !mounted) return;
      await ref.read(authApiProvider).totpEnable(secret: started.secret, code: code);
      if (!mounted) return;
      setState(() => _enabled = true);
      WasiatiSnack.success(context, l.secTotpEnabled);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final code = await _askForCode(title: l.secTotpTurnOff, blurb: l.secTotpBlurb);
      if (code == null || !mounted) return;
      await ref.read(authApiProvider).totpDisable(code);
      if (!mounted) return;
      setState(() => _enabled = false);
      WasiatiSnack.success(context, l.secTotpDisabled);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One sheet for both directions: enrolling and turning off each cost a current code.
  Future<String?> _askForCode({required String title, required String blurb, String? secret}) {
    final l = context.l10n;
    final ctrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(blurb, style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: sheetContext.tokens.muted)),
          if (secret != null) ...[
            const SizedBox(height: 14),
            Text(l.secTotpKey,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sheetContext.tokens.muted)),
            const SizedBox(height: 4),
            SelectableText(secret, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 1.2)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(labelText: l.secTotpCodeLabel, counterText: ''),
            onSubmitted: (v) => Navigator.of(sheetContext).pop(v.trim()),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(ctrl.text.trim()),
            child: Text(l.secTotpConfirm),
          ),
        ]),
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final on = _enabled == true;
    return _ActionRow(
      icon: on ? Icons.verified_outlined : Icons.smartphone_outlined,
      label: l.secTotpTitle,
      sub: on ? l.secTotpOn : l.secTotpBlurb,
      onTap: _busy ? null : (on ? _turnOff : _setUp),
    );
  }
}

/// Backup codes — the escape hatch that makes an authenticator safe to depend on.
///
/// An authenticator app lives on exactly one device, and on this product "I lost my phone"
/// must not mean "my family cannot reach my will": there is no identity check a support
/// human could perform that would not re-create the impersonation risk MFA exists to stop.
///
/// The UI's whole job is to make the user actually SAVE them. They are returned in
/// plaintext once and are unrecoverable afterwards, so the sheet says so plainly, offers
/// Copy all, and only dismisses on an explicit "I have saved them".
class _RecoveryCodesRow extends ConsumerStatefulWidget {
  const _RecoveryCodesRow();
  @override
  ConsumerState<_RecoveryCodesRow> createState() => _RecoveryCodesRowState();
}

class _RecoveryCodesRowState extends ConsumerState<_RecoveryCodesRow> {
  bool _busy = false;
  ({int remaining, int total, bool low})? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(authApiProvider).recoveryCodesStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // Unknown rather than wrong — the row still offers to generate, and the server is
      // the authority. Failing the settings screen over a count would be worse.
      if (mounted) setState(() => _status = null);
    }
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      final codes = await ref.read(authApiProvider).regenerateRecoveryCodes();
      if (!mounted) return;
      await _showCodes(codes);
      // Re-read rather than assume: the count on screen should be the server's, not ours.
      await _load();
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shown ONCE. Deliberately not dismissible by tapping away: a user who swipes this
  /// closed by accident has permanently lost codes they never saw, and the only remedy is
  /// generating a new set — which silently invalidates the ones they might have half-copied.
  Future<void> _showCodes(List<String> codes) {
    final l = context.l10n;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.secRcTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l.secRcSaveNow,
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: sheetContext.tokens.muted)),
          const SizedBox(height: 16),
          // Monospace and selectable: these get copied into a password manager or written
          // on paper, and a proportional font makes 0/O and 1/l harder than they need to be.
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final c in codes)
                SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 1.1)),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              if (sheetContext.mounted) WasiatiSnack.success(sheetContext, l.secRcCopied);
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: Text(l.secRcCopy),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(l.secRcDone),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _status;
    final none = s == null || s.total == 0;
    return _ActionRow(
      icon: none || s.low ? Icons.warning_amber_outlined : Icons.key_outlined,
      label: l.secRcTitle,
      sub: none
          ? l.secRcNone
          : (s.low ? l.secRcLow(s.remaining) : l.secRcRemaining(s.remaining, s.total)),
      onTap: _busy ? null : _generate,
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool padded;
  final bool tinted;
  const _Card({required this.child, this.padded = true, this.tinted = false});
  @override
  Widget build(BuildContext context) => WasiatiCard(
        padding: padded ? const EdgeInsets.all(18) : EdgeInsets.zero,
        radius: 16,
        borderColor: tinted ? WasiatiColors.dangerBorder : null,
        child: child,
      );
}


/// Inactivity check-in and the claim-initiation policy (spec §6).
///
/// Off by default: nobody is asked whether they are still alive without opting in.
/// The copy is careful — a trustee alert opens a human-reviewed claim path; it does
/// not declare anyone dead and it releases nothing.
class _CheckinCard extends ConsumerStatefulWidget {
  const _CheckinCard();
  @override
  ConsumerState<_CheckinCard> createState() => _CheckinCardState();
}

class _CheckinCardState extends ConsumerState<_CheckinCard> {
  bool _busy = false;

  /// Runs one settings mutation. Success/failure messaging happens HERE rather than
  /// inside the caller's async closure, so no BuildContext is carried across an await.
  Future<void> _run(Future<void> Function() action, {String? onSuccess}) async {
    setState(() => _busy = true);
    final fallback = context.l10n.settingsSaveFailed;
    try {
      await action();
      ref.invalidate(checkinStatusProvider);
      if (mounted && onSuccess != null) WasiatiSnack.success(context, onSuccess);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } catch (_) {
      if (mounted) WasiatiSnack.danger(context, fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _frequencyLabel(AppLocalizations l, String f) => switch (f) {
        'MONTHLY' => l.checkinMonthly,
        'YEARLY' => l.checkinYearly,
        _ => l.checkinQuarterly,
      };

  String _policyLabel(AppLocalizations l, String p) => switch (p) {
        'TRUSTEE_ONLY' => l.claimPolicyTrustee,
        'HEIRS_WITH_DOCUMENTS' => l.claimPolicyHeirs,
        _ => l.claimPolicyBoth,
      };

  // A resting default shown when the live status can't be loaded, so the section
  // degrades to its controls instead of a bare error string.
  static const _defaultStatus = CheckinStatus(
    enabled: false,
    frequency: 'QUARTERLY',
    lastConfirmedAt: null,
    remindersSent: 0,
    trusteeAlerted: false,
    claimInitPolicy: 'BOTH',
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final status = ref.watch(checkinStatusProvider);
    final api = ref.read(checkinApiProvider);

    return status.when(
      loading: () => const _Card(child: SizedBox(height: 64, child: Center(child: CircularProgressIndicator()))),
      // Never leave a raw error as the resting state — show the controls (spec §6).
      error: (_, __) => _cardBody(l, t, api, _defaultStatus, degraded: true),
      data: (s) => _cardBody(l, t, api, s),
    );
  }

  Widget _cardBody(AppLocalizations l, TextTheme t, CheckinApi api, CheckinStatus s, {bool degraded = false}) {
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (degraded) ...[
            Row(children: [
              Expanded(
                child: Text(l.checkinLoadError,
                    style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4)),
              ),
              TextButton(
                onPressed: _busy ? null : () => ref.invalidate(checkinStatusProvider),
                child: Text(l.wlTryAgain),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          Text(l.checkinSubtitle, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.enabled,
            title: Text(l.checkinEnable, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            onChanged: _busy ? null : (v) => _run(() => api.update(enabled: v)),
          ),
          if (s.enabled) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: s.frequency,
              decoration: InputDecoration(labelText: l.checkinFrequency),
              items: [
                for (final f in const ['MONTHLY', 'QUARTERLY', 'YEARLY'])
                  DropdownMenuItem(value: f, child: Text(_frequencyLabel(l, f))),
              ],
              onChanged: _busy ? null : (v) => v == null ? null : _run(() => api.update(frequency: v)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  '${l.checkinLastConfirmed}: ${s.lastConfirmedAt == null ? l.checkinNever : s.lastConfirmedAt!.toLocal().toString().split(' ').first}',
                  style: t.bodySmall?.copyWith(color: context.tokens.faint),
                ),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(api.confirmAlive, onSuccess: l.checkinConfirmed),
                child: Text(l.checkinConfirmNow),
              ),
            ]),
            if (s.trusteeAlerted) ...[
              const SizedBox(height: 10),
              Text(
                l.checkinTrusteeAlerted,
                style: t.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.4),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: context.tokens.hairline),
          const SizedBox(height: 16),
          Text(l.claimPolicyTitle, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: s.claimInitPolicy,
            isExpanded: true,
            items: [
              for (final p in const ['TRUSTEE_ONLY', 'HEIRS_WITH_DOCUMENTS', 'BOTH'])
                DropdownMenuItem(value: p, child: Text(_policyLabel(l, p))),
            ],
            onChanged: _busy
                ? null
                : (v) => v == null ? null : _run(() => api.setClaimPolicy(v), onSuccess: l.claimPolicySaved),
          ),
        ]),
      );
  }
}
