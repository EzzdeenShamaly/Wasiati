import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// intl also exports a `TextDirection`; hide it so the directive form fields can
// use Flutter's `TextDirection.ltr` (from material) without an ambiguity.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../commerce/application/entitlement_providers.dart';
import '../application/wills_providers.dart';
import '../domain/wills_models.dart';

/// Wills list (design 5a): each will as a card showing its seal status and a
/// one-line summary, plus a "create another" affordance.
class WillsListScreen extends ConsumerWidget {
  const WillsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wills = ref.watch(willsListProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          return SingleChildScrollView(
            // The bar's height rides on the content, so will rows slide under the glass
            // mid-scroll and the last one still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Mirrors the server's create cap (MAX_UNSEALED_WILLS = 3): only the
                  // UNSEALED wills count, so a sealed will alongside three drafts is still at
                  // the limit, but a sealed will with two drafts is not.
                  _Header(
                    wide: wide,
                    atCap: (wills.valueOrNull?.where((w) => w.status != 'SEALED').length ?? 0) >= 3,
                  ),
                  const SizedBox(height: 22),
                  wills.when(
                    loading: () => const _Loading(),
                    error: (e, _) => _Error(message: '$e', onRetry: () => ref.invalidate(willsListProvider)),
                    data: (list) => list.isEmpty
                        ? WasiatiEmptyState(
                            title: context.l10n.wlNoWillsTitle,
                            subtitle: context.l10n.wlNoWillsSubtitle,
                            ctaLabel: context.l10n.wlCreateYourWill,
                            onCta: () => context.go('/wills/new'),
                          )
                        : _Grid(list: list),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool wide;
  final bool atCap; // three unsealed drafts already exist — no more can be created
  const _Header({required this.wide, this.atCap = false});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    // The prototype header is the title + create button only — no subtitle.
    final titleBlock = Text(l.wlTitle, style: text.headlineMedium);
    final btn = FilledButton.icon(
      onPressed: atCap ? null : () => context.go('/wills/new'),
      icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
      label: Text(l.wlCreateWill),
    );
    final note = atCap
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.wlCapNote, style: text.bodySmall?.copyWith(color: context.tokens.faint)),
          )
        : const SizedBox.shrink();
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titleBlock,
        const SizedBox(height: 12),
        Align(alignment: AlignmentDirectional.centerStart, child: btn),
        note,
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: titleBlock),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [btn, note]),
    ]);
  }
}

class _Grid extends StatelessWidget {
  final List<Will> list;
  const _Grid({required this.list});
  @override
  Widget build(BuildContext context) {
    // Single-column horizontal rows (prototype 5a) — not a 2-col grid.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _WillRow(will: list[i], isPrimary: i == 0),
        ),
      // Only offer "create another" while under the create cap — up to three UNSEALED
      // drafts (MAX_UNSEALED_WILLS); the sealed will does not count.
      if (list.where((w) => w.status != 'SEALED').length < 3) const _CreateAnotherCard(),
      // Directives that live outside the will (prototype: after the second-will card).
      const SizedBox(height: 28),
      const _DocsSection(),
    ]);
  }
}

/// One will as a horizontal row (prototype 5a): 46px seal · info column ·
/// inline "Delete will" (primary sealed only) · "Open ›".
class _WillRow extends ConsumerWidget {
  final Will will;
  final bool isPrimary;
  const _WillRow({required this.will, required this.isPrimary});

  /// Deleting a will needs step-up re-authentication (spec §3, no exemption by status):
  /// confirm intent, request the SMS code, then delete with the entered OTP.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    // The sealed copy names signatures and witnesses, none of which a draft has. Telling
    // someone they are destroying a sealed will when they are discarding an unfinished one
    // is the kind of warning people learn to click past.
    final sealed = will.status == 'SEALED';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sealed ? l.wlDeleteWillTitle : l.wlDeleteDraftTitle),
        content: Text(sealed ? l.wlDeleteWillBody : l.wlDeleteDraftBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WasiatiColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.wlDeleteWill),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final api = ref.read(willsApiProvider);
    String? devCode;
    try {
      devCode = await api.sendWillDeleteCode(will.id);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
      return;
    }
    if (!context.mounted) return;
    // Only echo the code in a dev build, never in production.
    if (devCode != null && Env.isDev) WasiatiSnack.success(context, l.wdCodeSentDev(devCode));

    final otpCtrl = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.wlDeleteWillTitle),
        content: TextField(
          controller: otpCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l.wlDeleteOtpLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WasiatiColors.danger),
            onPressed: () => Navigator.pop(ctx, otpCtrl.text.trim()),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    otpCtrl.dispose();
    if (otp == null || otp.isEmpty || !context.mounted) return;

    try {
      await api.deleteWill(will.id, otp);
      ref.invalidate(willsListProvider);
      if (context.mounted) WasiatiSnack.success(context, l.wlDeleteDone);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final sealed = will.status == 'SEALED';
    final locale = l.localeName;

    // META line (prototype): "4 heirs · bequest 18% of the free third ·
    // 2 of 2 witnesses confirmed · updated 3 May" — clauses without data are omitted.
    final heirs = will.shariaShares.length;
    final bequestPct = will.bequests.fold<double>(0, (a, b) => a + b.sharePercent);
    final confirmed =
        will.witnesses.where((w) => w.status == 'SIGNED' || w.status == 'CONFIRMED').length;
    final requiredWitnesses = will.requiredWitnesses ?? 0;
    final meta = <String>[
      if (heirs > 0) context.digits(l.cwHeirCount(heirs)),
      if (bequestPct > 0) context.digits(l.wlMetaBequest(bequestPct.toStringAsFixed(bequestPct % 1 == 0 ? 0 : 1))),
      if (will.witnesses.isNotEmpty && requiredWitnesses > 0)
        context.digits(l.wlMetaWitnesses(confirmed, requiredWitnesses)),
      if (will.updatedAt != null) context.digits(l.wlMetaUpdated(DateFormat.MMMd(locale).format(will.updatedAt!))),
    ];

    final baseTitle = isPrimary ? l.wlPrimaryWill : l.wlAdditionalWill;
    final gold = context.tokens.goldInk;
    return WasiatiCard(
      padding: const EdgeInsets.all(20),
      // A draft opens in the guided steps so it can be EDITED; a sealed will opens
      // its detail page, which is the right home for something no longer being written.
      onTap: () => context.go(sealed ? '/wills/${will.id}' : '/wills/${will.id}/edit'),
      child: Row(children: [
        Seal(size: 46, status: sealed ? SealStatus.sealed : SealStatus.idle, filled: sealed),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(sealed ? l.wlTitleSealed(baseTitle) : baseTitle,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(meta.join(' · '), style: text.bodySmall?.copyWith(color: context.tokens.muted)),
            ],
            const SizedBox(height: 2),
            // VERSION line when sealed; otherwise the draft status sub-line.
            if (sealed && will.sealedAt != null)
              Text(context.digits(l.wlSealedSupersede(DateFormat.yMMMd(locale).format(will.sealedAt!))),
                  style: text.labelSmall?.copyWith(color: context.tokens.faint))
            else if (sealed)
              Text(l.wlSealed,
                  style: text.labelSmall?.copyWith(color: gold, fontWeight: FontWeight.w600))
            else
              Text(l.wlDraftNotSealed,
                  style: text.labelSmall?.copyWith(
                      color: context.tokens.faint, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        // Delete on EVERY will, draft included.
        //
        // The prototype (5a) put this only on the primary sealed will, and the app followed
        // it literally — so a draft could never be removed from the account at all. That is
        // the state an owner is in most often: an abandoned first attempt, a revision they
        // thought better of, a will started on the wrong madhhab. There was no way to clear
        // any of them, and the one-published-plus-one-draft cap (spec §3) meant a stuck
        // draft actively blocked starting a new one. Owner asked for it directly, which
        // outranks the prototype layout.
        //
        // Step-up auth still applies to all of them. Spec §3 requires re-authentication for
        // delete with no exemption by status, and a draft still holds the family's names and
        // shares, so it is not the kind of data to let a hijacked session discard silently.
        ...[
          OutlinedButton(
            onPressed: () => _confirmDelete(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.tokens.dangerInk,
              side: const BorderSide(color: WasiatiColors.danger, width: 1.5),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l.wlDeleteWill, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
        ],
        Text('${sealed ? l.wlOpen : l.wlContinue} ›',
            style: text.bodySmall?.copyWith(color: gold, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Second-will starter (prototype): dashed box — seal · "A second will" +
/// one-line rationale · a small outlined "Start" button.
class _CreateAnotherCard extends StatelessWidget {
  const _CreateAnotherCard();
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return DottedBorderBox(
      child: Row(children: [
        const Seal(size: 34, status: SealStatus.idle),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(l.wlSecondWillTitle,
                style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: context.tokens.muted)),
            const SizedBox(height: 3),
            Text(l.wlSecondWillBody,
                style: text.bodySmall?.copyWith(color: context.tokens.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: () => context.go('/wills/new'), child: Text(l.wlStart)),
      ]),
    );
  }
}

/// Directives that live outside the will (prototype "Wills" screen): a financial
/// power of attorney and a healthcare directive. Each card expands INLINE into a
/// prepare-&-sign form; saving executes the document server-side ("Save & sign"
/// is the only action) and the card flips to a SIGNED pill with the agent line.
/// Premium+ (spec §2) — lower tiers still see the cards, with a soft sell in
/// place of the button, never a wall.
class _DocsSection extends ConsumerStatefulWidget {
  const _DocsSection();
  @override
  ConsumerState<_DocsSection> createState() => _DocsSectionState();
}

class _DocsSectionState extends ConsumerState<_DocsSection> {
  String? _open; // 'POA' | 'HCD' | null — one form at a time (prototype docsExtra.open)

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final docs = ref.watch(directivesProvider).valueOrNull ?? const <DirectiveDoc>[];
    // Offer-side gate only: the server 403s a save below Premium regardless.
    final entitled = entitlementHas(ref.watch(entitlementProvider).valueOrNull, 'directives');
    DirectiveDoc? byType(String t) => docs.where((d) => d.type == t).firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 2, bottom: 12),
        child: Text(l.wlDocsExtraTitle.toUpperCase(),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.muted)),
      ),
      _DocCard(
        type: 'POA',
        icon: Icons.assignment_outlined,
        iconColor: context.tokens.goldInk,
        title: l.wlPoaTitle,
        subtitle: l.wlPoaSub,
        doc: byType('POA'),
        entitled: entitled,
        open: _open == 'POA',
        onToggle: (v) => setState(() => _open = v ? 'POA' : null),
      ),
      const SizedBox(height: 14),
      _DocCard(
        type: 'HCD',
        icon: Icons.monitor_heart_outlined,
        iconColor: dark ? WasiatiColors.greenSoft : WasiatiColors.bottleGreen,
        title: l.wlHcdTitle,
        subtitle: l.wlHcdSub,
        doc: byType('HCD'),
        entitled: entitled,
        open: _open == 'HCD',
        withWishes: true,
        onToggle: (v) => setState(() => _open = v ? 'HCD' : null),
      ),
    ]);
  }
}

class _DocCard extends StatelessWidget {
  final String type;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final DirectiveDoc? doc;
  final bool entitled;
  final bool open;
  final bool withWishes; // HCD adds the treatment-wishes textarea
  final ValueChanged<bool> onToggle;
  const _DocCard({
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.doc,
    required this.entitled,
    required this.open,
    required this.onToggle,
    this.withWishes = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final signed = doc?.signed ?? false;
    return WasiatiCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 30, color: iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 9,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  _StatusPill(signed: signed),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: text.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
              if (signed) ...[
                const SizedBox(height: 4),
                Text(l.wlDocAgentLine(doc!.agentName),
                    style: text.labelSmall?.copyWith(color: context.tokens.goldInk)),
              ],
              if (!entitled) ...[
                const SizedBox(height: 4),
                Text(l.wlDocGatedNudge, style: text.labelSmall?.copyWith(color: context.tokens.goldInk)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          if (!open) _cta(context),
        ]),
        if (open) ...[
          const SizedBox(height: 12),
          _DirectiveForm(type: type, doc: doc, withWishes: withWishes, onClose: () => onToggle(false)),
        ],
      ]),
    );
  }

  /// Trailing action while the form is closed: prepare/edit for the entitled,
  /// the plans soft-sell for everyone else (the card itself is never walled).
  Widget _cta(BuildContext context) {
    final l = context.l10n;
    if (!entitled) {
      return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        WasiatiChip(l.aiGatedBadge, kind: WasiatiChipKind.lockedFeature),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => context.go('/pricing'), child: Text(l.commonSeePlans)),
      ]);
    }
    final signed = doc?.signed ?? false;
    return signed
        ? OutlinedButton(onPressed: () => onToggle(true), child: Text(l.wlDocEdit))
        : FilledButton(onPressed: () => onToggle(true), child: Text(l.wlDocPrepare));
  }
}

/// The inline prepare-&-sign panel (prototype: sunken bg, hairline, radius 12,
/// padding 14). Save stays disabled until every field is filled — for the HCD
/// that includes the treatment wishes, exactly like the prototype's hOk gate.
class _DirectiveForm extends ConsumerStatefulWidget {
  final String type;
  final DirectiveDoc? doc;
  final bool withWishes;
  final VoidCallback onClose;
  const _DirectiveForm({required this.type, required this.doc, required this.withWishes, required this.onClose});
  @override
  ConsumerState<_DirectiveForm> createState() => _DirectiveFormState();
}

class _DirectiveFormState extends ConsumerState<_DirectiveForm> {
  late final _name = TextEditingController(text: widget.doc?.agentName ?? '');
  late final _phone = TextEditingController(text: widget.doc?.agentPhone ?? '');
  late final _email = TextEditingController(text: widget.doc?.agentEmail ?? '');
  late final _wishes = TextEditingController(text: widget.doc?.wishes ?? '');
  bool _busy = false;

  bool get _complete =>
      _name.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      (!widget.withWishes || _wishes.text.trim().isNotEmpty);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _wishes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(willsApiProvider).saveDirective(
            widget.type,
            agentName: _name.text.trim(),
            agentPhone: _phone.text.trim(),
            agentEmail: _email.text.trim(),
            wishes: widget.withWishes ? _wishes.text.trim() : null,
          );
      ref.invalidate(directivesProvider);
      if (!mounted) return;
      WasiatiSnack.success(context, context.l10n.wlDocToastSigned);
      widget.onClose();
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The prototype dims the gold save button to .38 while incomplete rather than
    // greying it; resolve the disabled state to the same gold, faded.
    final saveStyle = WasiatiButtons.goldSolid(context).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        final gold = dark ? WasiatiColors.goldDeepDark : WasiatiColors.goldDeep;
        return states.contains(WidgetState.disabled) ? gold.withValues(alpha: 0.38) : gold;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        final ink = dark ? WasiatiColors.inkNavy : WasiatiColors.onDark;
        return states.contains(WidgetState.disabled) ? ink.withValues(alpha: 0.62) : ink;
      }),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Sunken: the page background showing through a well in the card.
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: context.tokens.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          final name = _DocField(
              label: l.wlDocAgentNameLbl, controller: _name, hint: l.cwFullNamePh, onChanged: (_) => setState(() {}));
          final phone = _DocField(
              label: l.cwPhoneLbl,
              controller: _phone,
              hint: l.cwPhonePh,
              ltr: true,
              keyboard: TextInputType.phone,
              onChanged: (_) => setState(() {}));
          final email = _DocField(
              label: l.cwEmailLbl,
              controller: _email,
              hint: l.cwEmailPh,
              ltr: true,
              keyboard: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}));
          if (box.maxWidth >= 560) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: name),
              const SizedBox(width: 10),
              Expanded(child: phone),
              const SizedBox(width: 10),
              Expanded(child: email),
            ]);
          }
          return Column(children: [name, const SizedBox(height: 10), phone, const SizedBox(height: 10), email]);
        }),
        if (widget.withWishes) ...[
          const SizedBox(height: 10),
          _DocField(
              label: l.wlDocWishesLbl,
              controller: _wishes,
              hint: l.wlDocWishesPh,
              maxLines: 3,
              onChanged: (_) => setState(() {})),
        ],
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(
            style: saveStyle,
            onPressed: _complete && !_busy ? _save : null,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.wlDocSaveSign),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: widget.onClose, child: Text(l.commonCancel)),
        ]),
      ]),
    );
  }
}

/// Compact labelled field for the directive forms — the registry's `_RegField`
/// shape (tiny caps label over a dense input), local to this screen.
class _DocField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool ltr;
  final int maxLines;
  final TextInputType? keyboard;
  final ValueChanged<String> onChanged;
  const _DocField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.ltr = false,
    this.maxLines = 1,
    this.keyboard,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.faint)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(hintText: hint, isDense: true),
      ),
    ]);
  }
}

/// Signed (green) / Not started (muted outline) status pill for the directives.
class _StatusPill extends StatelessWidget {
  final bool signed;
  const _StatusPill({required this.signed});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: signed ? (dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint) : null,
        borderRadius: BorderRadius.circular(99),
        border: signed ? null : Border.all(color: context.tokens.hairline),
      ),
      child: Text(
        (signed ? l.wlDocSigned : l.wlDocNotStarted).toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: signed ? context.tokens.successInk : context.tokens.faint,
        ),
      ),
    );
  }
}

// --- shared bits ---------------------------------------------------------
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(color: context.tokens.hairline),
      child: Padding(padding: const EdgeInsets.all(28), child: child),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  _DashedRectPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Text(context.l10n.wlLoadErrorTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.wlTryAgain)),
        ]),
      );
}

