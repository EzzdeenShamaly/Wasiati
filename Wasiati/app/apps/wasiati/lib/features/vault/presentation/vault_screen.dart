import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/vault_providers.dart';
import '../data/vault_api.dart';
import '../data/vault_crypto.dart';
import '../domain/vault_models.dart';
import '../domain/password_import.dart';

/// Encrypted vault (design 7a): passphrase unlock (Face ID primary on device),
/// then client-side-encrypted secrets with reveal/hide. The server only ever
/// holds ciphertext.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});
  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _passphrase = TextEditingController();
  SecretKey? _kek;
  bool _unlocking = false;
  final Map<String, String> _revealed = {};

  /// Security window (spec §55): the vault re-locks itself 90s after unlock, and
  /// each revealed secret re-hides itself 10s after it is shown.
  static const _autoLockSeconds = 90;
  static const _revealSeconds = 10;
  Timer? _autoLockTimer;
  int _autoLockLeft = _autoLockSeconds;
  final Map<String, Timer> _revealTimers = {};

  @override
  void dispose() {
    _passphrase.dispose();
    _autoLockTimer?.cancel();
    for (final t in _revealTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  /// (Re)start the 90s idle countdown. Called on unlock and on any activity
  /// (revealing a secret) so active use keeps the vault open.
  void _startAutoLock() {
    _autoLockTimer?.cancel();
    setState(() => _autoLockLeft = _autoLockSeconds);
    _autoLockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_autoLockLeft <= 1) {
        _lock();
      } else {
        setState(() => _autoLockLeft -= 1);
      }
    });
  }

  Future<void> _unlock() async {
    // The vault's confidentiality rests entirely on this passphrase (the server holds
    // only ciphertext), so hold it to the same >=10 floor as the account password —
    // a 6-char secret is GPU-brute-forceable offline against a stolen ciphertext.
    if (_passphrase.text.length < 10) {
      WasiatiSnack.danger(context, context.l10n.vaultPassphraseShort);
      return;
    }
    setState(() => _unlocking = true);
    try {
      final api = ref.read(vaultApiProvider);
      final kdf = await api.kdf();
      final kek = await VaultCrypto.deriveKek(_passphrase.text, kdf.salt);

      // THE CHECK THIS SCREEN DID NOT HAVE.
      //
      // Unlock used to validate the passphrase's LENGTH and nothing else, then render the
      // vault. A typo derived a different KEK and unlocked anyway — labels are stored in
      // plaintext, so the list looked exactly right — and every secret added afterwards was
      // encrypted under a key the user would never reproduce. Nothing reported a problem;
      // they found out later, when half the vault would not open and nobody, including us,
      // could do anything about it (DECISIONS §19).
      if (!await _passphraseOpensVault(api, kdf, kek)) {
        if (!mounted) return;
        setState(() => _unlocking = false);
        WasiatiSnack.danger(context, context.l10n.vaultPassphraseWrong);
        return;
      }

      if (!mounted) return;
      setState(() {
        _kek = kek;
        _unlocking = false;
      });
      _startAutoLock();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _unlocking = false);
        WasiatiSnack.danger(context, e.message);
      }
    }
  }

  /// Whether this passphrase is the one this vault was locked with.
  ///
  /// Three cases, and the ordering matters:
  ///   * a verifier exists — check it, and that is the whole answer;
  ///   * no verifier but the vault HOLDS items — prove the key against real ciphertext,
  ///     then adopt a verifier so the next unlock is cheap and certain;
  ///   * no verifier and no items — nothing to check against, so this passphrase becomes
  ///     the vault's. Recording it BEFORE anything is written under it is what stops the
  ///     very next unlock from being a coin flip.
  ///
  /// Fails CLOSED throughout: refusing to unlock costs a retry, unlocking under the wrong
  /// key costs the secrets.
  Future<bool> _passphraseOpensVault(VaultApi api, VaultKdf kdf, SecretKey kek) async {
    final existing = kdf.verifier;
    if (existing != null) return VaultCrypto.verify(existing, kek);

    if (kdf.hasItems) {
      final items = await api.list();
      if (items.isEmpty) return false; // reports items but returns none — do not adopt
      final probe = items.first;
      if (!await VaultCrypto.canDecrypt(probe.ciphertext, probe.encryptedDataKey, kek)) return false;
    }

    // Proven, or provably empty. Adopt — and tolerate losing the race to another device,
    // since the server keeps the first verifier and this key matched the same vault.
    try {
      await api.setVerifier(await VaultCrypto.makeVerifier(kek));
    } catch (_) {
      // Not fatal: the check above already established the key. A missing verifier only
      // means the next unlock repeats this work.
    }
    return true;
  }

  void _lock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    for (final t in _revealTimers.values) {
      t.cancel();
    }
    _revealTimers.clear();
    setState(() {
      _kek = null;
      _revealed.clear();
      _passphrase.clear();
    });
  }

  Future<void> _addItem() async {
    final label = TextEditingController();
    final site = TextEditingController();
    final user = TextEditingController();
    final secret = TextEditingController();
    final notes = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.vaultAddSecretTitle),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // The field structure IS the guidance: one entry per account, with the
                // site, the sign-in identity and the secret each in its own place —
                // because the person who eventually reads this is not the person who
                // wrote it, and "P@ss123" with no site and no username helps nobody.
                Text(ctx.l10n.vaultAddHint,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: ctx.tokens.muted, height: 1.5)),
                const SizedBox(height: 14),
                TextField(controller: label, decoration: InputDecoration(labelText: ctx.l10n.vaultLabelField)),
                const SizedBox(height: 10),
                TextField(controller: site, decoration: InputDecoration(labelText: ctx.l10n.vaultSiteField)),
                const SizedBox(height: 10),
                TextField(controller: user, decoration: InputDecoration(labelText: ctx.l10n.vaultUserField)),
                const SizedBox(height: 10),
                TextField(controller: secret, decoration: InputDecoration(labelText: ctx.l10n.vaultSecretField), maxLines: 2),
                const SizedBox(height: 10),
                TextField(controller: notes, decoration: InputDecoration(labelText: ctx.l10n.vaultNotesField), maxLines: 2),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.vaultEncryptSave)),
          ],
        ),
      );
      if (ok != true || label.text.trim().isEmpty || _kek == null) return;
      // The same labeled-lines convention the password IMPORT already writes
      // (ImportedPassword.secretValue) — deliberately plain text, not JSON: whoever
      // eventually reads this — a spouse, years from now, in an exported file — needs
      // no parser, just eyes. A lone secret with no context stays a bare value.
      final structured = [
        if (site.text.trim().isNotEmpty) 'URL: ${site.text.trim()}',
        if (user.text.trim().isNotEmpty) 'Username: ${user.text.trim()}',
        if (secret.text.trim().isNotEmpty) 'Password: ${secret.text.trim()}',
        if (notes.text.trim().isNotEmpty) 'Notes: ${notes.text.trim()}',
      ];
      final value = (site.text.trim().isEmpty && user.text.trim().isEmpty && notes.text.trim().isEmpty)
          ? secret.text
          : structured.join('\n');
      try {
        final enc = await VaultCrypto.encrypt(value, _kek!);
        await ref.read(vaultApiProvider).add(
              label: label.text.trim(),
              ciphertext: enc.ciphertext,
              encryptedDataKey: enc.encryptedDataKey,
            );
        ref.invalidate(vaultListProvider);
      } catch (e) {
        if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
      }
    } finally {
      label.dispose();
      site.dispose();
      user.dispose();
      secret.dispose();
      notes.dispose();
    }
  }

  /// Import from a Chrome/Apple Passwords CSV. Everything is parsed and encrypted on
  /// this device (see VaultCrypto) before it is saved; the pasted text never leaves
  /// the device unencrypted. Requires the vault to be unlocked (we have the KEK).
  Future<void> _importPasswords() async {
    final kek = _kek;
    if (kek == null) return;
    final entries = await showModalBottomSheet<List<ImportedPassword>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ImportSheet(),
    );
    if (entries == null || entries.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final api = ref.read(vaultApiProvider);
    var ok = 0;
    try {
      for (final e in entries) {
        final enc = await VaultCrypto.encrypt(e.secretValue, kek);
        await api.add(label: e.label, ciphertext: enc.ciphertext, encryptedDataKey: enc.encryptedDataKey);
        ok++;
      }
      ref.invalidate(vaultListProvider);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('${context.digits(l.vaultImportDone(ok))} ${l.vaultImportDeleteFile}')));
      }
    } on ApiException catch (err) {
      if (mounted) WasiatiSnack.danger(context, err.message);
    }
  }

  /// Export every secret as a readable text file — decrypted HERE, with the KEK this
  /// session proved, exactly like the import in reverse: plaintext exists only on this
  /// device, and only because the user asked for it by name.
  ///
  /// Why this exists: the vault's job is to outlive its owner, and "in the vault" is not
  /// the only place a family may need these — a printed sheet in a home safe is a
  /// legitimate, sometimes required, companion (the same reasoning as the recovery-codes
  /// design). The gate is a warning dialog that says plainly what the file is: every
  /// secret, readable by anyone who holds it.
  ///
  /// A .txt, not a PDF or CSV: greppable, printable, diffable, no renderer between the
  /// user and their own data — and visibly NOT a document to leave lying around.
  Future<void> _exportSecrets() async {
    final kek = _kek;
    if (kek == null) return;
    final l = context.l10n;

    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.vaultExportWarnTitle),
        content: Text(ctx.l10n.vaultExportWarnBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.vaultExportConfirm)),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    try {
      final items = await ref.read(vaultApiProvider).list();
      final lines = <String>[
        l.vaultExportHeader(DateTime.now().toIso8601String().substring(0, 10)),
        l.vaultExportHeaderWarn,
        '',
      ];
      // The KEK was proved at unlock (verifier or probe), so a decrypt failure here is a
      // corrupted row, not a wrong key. Skip it and SAY so — silently exporting fewer
      // secrets than the vault holds is how a family finds out at the worst moment.
      var skipped = 0;
      for (final it in items) {
        try {
          final value = await VaultCrypto.decrypt(it.ciphertext, it.encryptedDataKey, kek);
          lines
            ..add('— ${it.label} —')
            ..add(value)
            ..add('');
        } catch (_) {
          skipped++;
        }
      }
      await FileSaver.instance.saveFile(
        name: 'wasiati-vault',
        bytes: Uint8List.fromList(utf8.encode(lines.join('\n'))),
        fileExtension: 'txt',
        mimeType: MimeType.text,
      );
      if (mounted) {
        final done = context.digits(l.vaultExportDone(items.length - skipped));
        final tail = skipped > 0 ? ' ${context.digits(l.vaultExportSkipped(skipped))}' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$done$tail')));
      }
      _startAutoLock(); // exporting is activity, same as revealing
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding of each view instead (see AppShell's extendBody).
      body: SafeArea(bottom: false, child: _kek == null ? _unlockView(context) : _vaultView(context)),
    );
  }

  // --- unlock ------------------------------------------------------------
  Widget _unlockView(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        // Padding the content rather than the viewport keeps this card exactly where
        // it was: the scroll view shrink-wraps to content + bar, so Center offsets it
        // back above the glass. On a short screen it still scrolls clear of it.
        padding: const EdgeInsets.all(30) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Seal(size: 74, status: SealStatus.locked, filled: true),
            const SizedBox(height: 20),
            Text(l.vaultUnlockTitle, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.vaultUnlockSubtitle,
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => WasiatiSnack.success(context, l.vaultFaceIdSnack),
                icon: const Icon(Icons.face_outlined, size: 18),
                label: Text(l.vaultUnlockFaceId),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Divider(color: context.tokens.hairline)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(l.vaultOr, style: t.bodySmall?.copyWith(color: context.tokens.faint))),
              Expanded(child: Divider(color: context.tokens.hairline)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _passphrase,
              obscureText: true,
              textAlign: TextAlign.center,
              decoration: InputDecoration(hintText: l.vaultPassphraseHint),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _unlocking ? null : _unlock,
                child: _unlocking
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.vaultUnlockPassphrase),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.tokens.hairline),
              ),
              child: Text(l.vaultForgotWarn,
                  textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ),
          ]),
        ),
      ),
    );
  }

  // --- unlocked ----------------------------------------------------------
  Widget _vaultView(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final items = ref.watch(vaultListProvider);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      return SingleChildScrollView(
        // The bar's height rides on the content, so secret cards slide under the glass
        // mid-scroll and the warning callout still comes to rest clear of it.
        padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 12,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(l.vaultTitle, style: t.headlineMedium),
                    const SizedBox(height: 2),
                    Text(l.vaultSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: context.tokens.warningInk, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(context.digits(l.vaultAutoLockIn(_autoLockLeft)),
                          style: t.bodySmall?.copyWith(color: context.tokens.warningInk, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(width: 12),
                    FilledButton.icon(onPressed: _addItem, icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 16), label: Text(l.vaultAddSecretBtn)),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                        onPressed: _importPasswords,
                        icon: const WasiatiIcon(svg: WasiatiIcons.download, size: 16),
                        label: Text(l.vaultImport)),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _exportSecrets, child: Text(l.vaultExport)),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _lock, child: Text(l.vaultLockNow)),
                  ]),
                ],
              ),
              const SizedBox(height: 20),
              items.when(
                loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => _errorOrUpgrade(context, e),
                data: (list) => list.isEmpty
                    ? WasiatiEmptyState(
                        title: l.vaultEmptyTitle,
                        subtitle: l.vaultEmptySubtitle,
                        seal: SealStatus.locked,
                        ctaLabel: l.vaultAddSecretTitle,
                        onCta: _addItem,
                      )
                    : _grid(context, list, wide),
              ),
              const SizedBox(height: 10),
              Text(l.vaultRevealFootnote, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
              const SizedBox(height: 18),
              _warningCallout(context),
            ]),
          ),
        ),
      );
    });
  }

  Widget _grid(BuildContext context, List list, bool wide) {
    final cards = [for (final it in list) _SecretCard(item: it, screen: this)];
    if (!wide) {
      return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)]);
    }
    return Wrap(spacing: 16, runSpacing: 16, children: [
      for (final c in cards) SizedBox(width: (1000 - 16) / 2 - 0.5, child: c),
    ]);
  }

  Widget _warningCallout(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WasiatiColors.goldBorder),
      ),
      child: Row(children: [
        const Seal(size: 22, status: SealStatus.sealed, filled: true),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.vaultWarnCallout,
            style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5),
          ),
        ),
      ]),
    );
  }

  // exposed for _SecretCard
  bool isRevealed(String id) => _revealed.containsKey(id);
  String revealedValue(String id) => _revealed[id] ?? '';
  Future<void> toggleReveal(dynamic it) async {
    if (_revealed.containsKey(it.id)) {
      _hide(it.id);
      return;
    }
    // Snapshot the KEK: if auto-lock raced the tap, _kek is already null (was a `!` NPE).
    final kek = _kek;
    if (kek == null) return;
    // AES-GCM authenticates: a wrong key or a corrupted blob THROWS, it does not produce
    // garbage. Nothing caught it, so the tap did nothing — silently, forever — while the
    // sibling deleteItem below surfaces its failures as a snack. The realistic case is an
    // item written under a mistyped passphrase before the unlock verifier existed: that
    // secret is permanently undecryptable under this key, and the one honest thing the
    // app can do is say so, and say what to try (another passphrase may open it).
    final String v;
    try {
      v = await VaultCrypto.decrypt(it.ciphertext, it.encryptedDataKey, kek);
    } catch (_) {
      if (mounted) WasiatiSnack.danger(context, context.l10n.vaultDecryptFailed);
      return;
    }
    // Re-check after the await: if the vault locked while decrypting, do NOT push the
    // plaintext back into state — that would resurrect a secret past the lock.
    if (!mounted || _kek == null) return;
    setState(() => _revealed[it.id] = v);
    // Auto-hide this secret after 10s, and treat revealing as activity so the
    // 90s idle auto-lock restarts.
    _revealTimers[it.id]?.cancel();
    _revealTimers[it.id] = Timer(const Duration(seconds: _revealSeconds), () => _hide(it.id));
    _startAutoLock();
  }

  void _hide(String id) {
    _revealTimers.remove(id)?.cancel();
    if (mounted) setState(() => _revealed.remove(id));
  }

  Future<void> deleteItem(String id) async {
    try {
      await ref.read(vaultApiProvider).delete(id);
      ref.invalidate(vaultListProvider);
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  Widget _errorOrUpgrade(BuildContext context, Object e) {
    if (isPaywall(e)) {
      return WasiatiUpgradePrompt(
        title: context.l10n.vaultUpgradeTitle,
        body: context.l10n.vaultUpgradeBody,
        seePlansLabel: context.l10n.commonSeePlans,
        onSeePlans: () => context.go('/pricing'),
      );
    }
    return Center(child: Text('$e', style: Theme.of(context).textTheme.bodyMedium));
  }
}

class _SecretCard extends StatelessWidget {
  final dynamic item;
  final _VaultScreenState screen;
  const _SecretCard({required this.item, required this.screen});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final revealed = screen.isRevealed(item.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Row(children: [
        const Seal(size: 34, status: SealStatus.sealed, filled: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            revealed
                ? SelectableText(screen.revealedValue(item.id), style: t.bodySmall)
                : Text('•••••••••••••', style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
          onPressed: () => screen.toggleReveal(item),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => screen.deleteItem(item.id),
        ),
      ]),
    );
  }
}


/// Paste-based Chrome/Apple password import. Parses on-device; returns the parsed
/// entries to the caller, which encrypts each before saving. The raw CSV stays in
/// this widget's memory and is never sent anywhere.
class _ImportSheet extends StatefulWidget {
  const _ImportSheet();
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _csv = TextEditingController();
  PasswordImportResult _result = const PasswordImportResult([], 0);

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  void _reparse() => setState(() => _result = parsePasswordCsv(_csv.text));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final count = _result.entries.length;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.vaultImportTitle, style: t.titleLarge),
          const SizedBox(height: 8),
          Text(l.vaultImportHow, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _csv,
            minLines: 5,
            maxLines: 10,
            onChanged: (_) => _reparse(),
            decoration: InputDecoration(labelText: l.vaultImportPaste, alignLabelWithHint: true),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (_csv.text.trim().isNotEmpty)
            Text(
              count > 0
                  ? [context.digits(l.vaultImportPreview(count)), if (_result.skipped > 0) context.digits(l.vaultImportSkipped(_result.skipped))].join('  ')
                  : l.vaultImportNone,
              style: t.bodySmall?.copyWith(color: count > 0 ? context.tokens.successInk : context.tokens.warningInk),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: count == 0 ? null : () => Navigator.pop(context, _result.entries),
            child: Text(context.digits(l.vaultImportRun(count))),
          ),
        ]),
      ),
    );
  }
}
