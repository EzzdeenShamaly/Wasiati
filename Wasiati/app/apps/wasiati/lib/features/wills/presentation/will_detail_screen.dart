import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/back_nav.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/wills_providers.dart';
import '../application/will_pdf.dart';
import '../domain/wills_models.dart';
import '../domain/will_export_gate.dart';
import '../domain/will_opening_text.dart';

/// Which section to bring into view on arrival (`?focus=` on the route).
///
/// The dashboard's estate tiles each stand for one section of this page. Landing at
/// the top of a long two-column page and leaving the owner to find the thing they
/// tapped is how "heir contacts takes me to the wrong page" happens — the page was
/// right, the position was not.
enum WillSection { heirs, witnesses, trustees }

WillSection? willSectionFrom(String? raw) => switch (raw) {
      'heirs' => WillSection.heirs,
      'witnesses' => WillSection.witnesses,
      'trustees' => WillSection.trustees,
      _ => null,
    };

/// Will detail (design 5c): the sealed/draft will — shares table, bequests with
/// the free-third cap, witnesses & trustees with SMS status, and the owner's
/// personal message. Sealing itself happens on the Review & seal step (5d).
class WillDetailScreen extends ConsumerStatefulWidget {
  final String willId;

  /// Section to scroll to once the will has loaded. Null = start at the top.
  final WillSection? focus;
  const WillDetailScreen({super.key, required this.willId, this.focus});

  @override
  ConsumerState<WillDetailScreen> createState() => _WillDetailScreenState();
}

class _WillDetailScreenState extends ConsumerState<WillDetailScreen> {
  final _heirsKey = GlobalKey();
  final _witnessesKey = GlobalKey();
  final _trusteesKey = GlobalKey();

  /// Only ever scrolls once. The will provider can rebuild (a witness confirms, the
  /// SMS status refreshes) and yanking the page back to the anchor mid-read would be
  /// worse than never scrolling at all.
  bool _focused = false;

  void _focusSection() {
    if (_focused || widget.focus == null) return;
    final key = switch (widget.focus!) {
      WillSection.heirs => _heirsKey,
      WillSection.witnesses => _witnessesKey,
      WillSection.trustees => _trusteesKey,
    };
    final ctx = key.currentContext;
    if (ctx == null) return; // not built yet — try again on the next frame
    _focused = true;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic, alignment: 0.05);
  }

  @override
  Widget build(BuildContext context) {
    final willId = widget.willId;
    final will = ref.watch(willProvider(willId));
    // The anchors only exist once the data branch has built, so this is scheduled on
    // every frame until it finds one and latches.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSection());
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: will.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(message: '$e', onRetry: () => ref.invalidate(willProvider(willId))),
          data: (w) => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 860;
            return SingleChildScrollView(
              // The bar's height rides on the content, so the will's cards slide under the
              // glass mid-scroll and the last one still comes to rest clear of it.
              padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                  EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Breadcrumb back to the wills list — every will page can walk back up.
                    WasiatiBackLink(
                      label: context.l10n.wdBackToWills,
                      onTap: () => context.goBack('/wills'),
                    ),
                    const SizedBox(height: 6),
                    _Header(will: w),
                    const SizedBox(height: 20),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 14, child: _LeftColumn(will: w, heirsKey: _heirsKey)),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 10,
                            child: _RightColumn(
                              willId: w.id,
                              will: w,
                              witnessesKey: _witnessesKey,
                              trusteesKey: _trusteesKey,
                            ),
                          ),
                        ]),
                      )
                    else ...[
                      _LeftColumn(will: w, heirsKey: _heirsKey),
                      const SizedBox(height: 16),
                      _RightColumn(
                        willId: w.id,
                        will: w,
                        witnessesKey: _witnessesKey,
                        trusteesKey: _trusteesKey,
                      ),
                    ],
                    // The document itself is NOT here. It used to be the last child of this
                    // column — under the header, the shares, the bequests, the witnesses and
                    // the trustee panel — which put it below the fold on every viewport, so
                    // the one thing worth reading closely was the one thing nobody saw. The
                    // prototype gives it its own page (route `willDoc`), reached by the
                    // "View document" button in the header above. So does this now.
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  final Will will;
  const _Header({required this.will});
  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _downloading = false;
  bool _revising = false;
  bool _unpublishing = false;

  /// Downloads the document the preview is showing — same format, same share display, same
  /// language — instead of asking again in a sheet. The choices are already on the page, so
  /// a second dialog could only disagree with what the owner just read.
  Future<void> _downloadPdf() async {
    setState(() => _downloading = true);
    final choice = ref.read(willPreviewChoiceProvider);
    await shareWillPdf(
      context,
      ref,
      widget.will.id,
      format: choice.format,
      display: choice.display,
      lang: Localizations.localeOf(context).languageCode == 'ar' ? 'ar' : 'en',
    );
    if (mounted) setState(() => _downloading = false);
  }

  /// "Reopen to edit" on a sealed will = POST /wills/:id/revise. Opens a fresh
  /// DRAFT carrying the sealed will's content and lands on it; the sealed will
  /// stays in force until the revision is sealed in its turn. Until this was
  /// wired the button only ever showed a snackbar, so a published will could
  /// never be revised from the app at all.
  Future<void> _revise() async {
    final l = context.l10n;
    // BASIC is immutable server-side (403); the pre-existing snack says so in
    // the user's language without burning a request.
    if (widget.will.tier == 'BASIC') {
      WasiatiSnack.success(context, l.wdReopenSnack);
      return;
    }
    setState(() => _revising = true);
    try {
      final draft = await ref.read(willsApiProvider).revise(widget.will.id);
      ref.invalidate(willsListProvider);
      if (!mounted) return;
      WasiatiSnack.success(context, l.wdReviseOpened);
      context.go('/wills/${draft.id}');
    } on ApiException catch (e) {
      // "You already have a draft…" / "Only a published (sealed) will…" —
      // specific, so shown verbatim.
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  /// SEALED -> DRAFT = POST /wills/:id/unpublish (spec §3: "Delete/unpublish
  /// require re-authentication"). Confirm intent, request the step-up code —
  /// SMS when the owner has a phone, otherwise their verified email; the
  /// server's `via` names whichever channel was actually used so the prompt
  /// never claims an SMS that went to email — then unpublish with the code.
  /// Until this was wired only delete could take a sealed will out of force.
  Future<void> _unpublish() async {
    final l = context.l10n;
    final will = widget.will;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.wdUnpublishTitle),
        content: Text(l.wdUnpublishBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WasiatiColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.wdUnpublish),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _unpublishing = true);
    final api = ref.read(willsApiProvider);
    final ({String via, String? devCode}) sent;
    try {
      sent = await api.requestStepUpOtp(will.id);
    } on ApiException catch (e) {
      if (mounted) {
        WasiatiSnack.danger(context, e.message);
        setState(() => _unpublishing = false);
      }
      return;
    }
    if (!mounted) return;
    // Only echo the code in a dev build, never in production.
    if (sent.devCode != null && Env.isDev) WasiatiSnack.success(context, l.wdCodeSentDev(sent.devCode!));

    final otpCtrl = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.wdUnpublishTitle),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            sent.via == 'email' ? l.wdStepUpEmailSent : l.wdStepUpSmsSent,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: ctx.tokens.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: otpCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: l.wdStepUpCodeLabel),
            onSubmitted: (_) => Navigator.pop(ctx, otpCtrl.text.trim()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WasiatiColors.danger),
            onPressed: () => Navigator.pop(ctx, otpCtrl.text.trim()),
            child: Text(l.wdUnpublish),
          ),
        ],
      ),
    );
    otpCtrl.dispose();
    if (otp == null || otp.isEmpty) {
      if (mounted) setState(() => _unpublishing = false);
      return;
    }

    try {
      await api.unpublish(will.id, otp);
      // The will (status), its witnesses (signatures cleared) and the list row
      // all changed server-side — refetch the lot.
      ref.invalidate(willProvider(will.id));
      ref.invalidate(witnessesProvider(will.id));
      ref.invalidate(willsListProvider);
      if (mounted) WasiatiSnack.success(context, l.wdUnpublishDone);
    } on ApiException catch (e) {
      // "Invalid or expired confirmation code." / "Only a published (sealed)
      // will…" — specific, so shown verbatim.
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _unpublishing = false);
    }
  }

  /// The disabled-button note: names exactly who is still outstanding
  /// ("Waiting on: 1 witness · trustee"), or the interim text while we don't yet know.
  String? _waitingOn(AppLocalizations l, WillExportGate gate) {
    if (!gate.ready) return l.wdExportChecking;
    if (!gate.hasOutstanding) return null;
    final parties = <String>[
      if (gate.outstandingWitnesses > 0) context.digits(l.wdExportWaitingWitnesses(gate.outstandingWitnesses)),
      if (gate.trusteeOutstanding) l.wdExportWaitingTrustee,
    ];
    return l.wdExportWaitingOn(parties.join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final will = widget.will;
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final sealed = will.status == 'SEALED' || will.locked;
    final gate = WillExportGate.of(
      requiredWitnesses: will.requiredWitnesses ?? 2,
      witnesses: ref.watch(witnessesProvider(will.id)).asData?.value,
      trustees: ref.watch(trusteesProvider(will.id)).asData?.value,
    );
    final waitingOn = _waitingOn(l, gate);
    final title = Row(children: [
      Seal(size: 56, status: sealed ? SealStatus.sealed : SealStatus.idle, filled: sealed),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.wdMyPrimaryWill, style: t.headlineSmall),
          const SizedBox(height: 3),
          Text(sealed ? l.wdSealedEstate(will.tier) : l.wdDraftNotSealed,
              style: t.bodyMedium?.copyWith(
                  color: context.tokens.goldInk,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
    final actions = sealed
        ? [
            // Truly SEALED only (not a locked draft): take the will out of force.
            if (will.status == 'SEALED') ...[
              OutlinedButton(
                  onPressed: _unpublishing ? null : _unpublish,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.tokens.dangerInk,
                    side: const BorderSide(color: WasiatiColors.danger, width: 1.5),
                  ),
                  child: _unpublishing
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.wdUnpublish)),
              const SizedBox(width: 10),
            ],
            // One will + one draft is the cap, so revising while a draft already exists
            // can ONLY fail — the server answers "You already have a draft". Offering
            // "Reopen to edit" there is a button whose single outcome is an error, and it
            // reads as the sealed will simply refusing to open. The app already knows the
            // draft exists, so it offers the action that works instead: go to it.
            Builder(builder: (context) {
              final existingDraft = ref
                  .watch(willsListProvider)
                  .valueOrNull
                  ?.where((w) => w.status == 'DRAFT' && w.id != widget.will.id)
                  .firstOrNull;
              if (existingDraft != null) {
                return OutlinedButton(
                  onPressed: () => context.go('/wills/${existingDraft.id}'),
                  child: Text(l.wdContinueDraft),
                );
              }
              return OutlinedButton(
                  onPressed: _revising ? null : _revise,
                  child: _revising
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.wdReopenToEdit));
            }),
            const SizedBox(width: 10),
            // Opens the document on its own page (the prototype's willDoc). UNGATED: the
            // gate below is about exporting a copy, never about reading your own will.
            OutlinedButton(
              onPressed: () => context.go('/wills/${will.id}/document'),
              child: Text(l.wdViewDocument),
            ),
            const SizedBox(width: 10),
            // Gated: no export until the witnesses have signed AND the trustee has
            // confirmed. The will itself stays fully viewable — only the PDF waits.
            FilledButton(
                onPressed: (_downloading || !gate.exportable) ? null : _downloadPdf,
                child: _downloading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.wdDownloadPdf)),
          ]
        : [
            FilledButton(
              onPressed: () => context.go('/wills/${will.id}/review'),
              child: Text(l.wdReviewSeal),
            ),
          ];
    // Only meaningful next to the (sealed-only) download button.
    final note = sealed && waitingOn != null ? _ExportWaitingNote(text: waitingOn) : null;

    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 640) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title,
          const SizedBox(height: 14),
          // Wrap, not Row: three sealed-will actions overflow a phone width.
          Wrap(runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          if (note != null) ...[const SizedBox(height: 8), note],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: title), ...actions]),
        if (note != null) ...[
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: note),
        ],
      ]);
    });
  }
}

/// Why the Download PDF button is disabled — names exactly who has still to sign
/// or confirm ("Waiting on: 1 witness · trustee"), so the owner knows who to chase
/// rather than being left with a dead button.
class _ExportWaitingNote extends StatelessWidget {
  const _ExportWaitingNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.schedule, size: 14, color: context.tokens.muted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted),
        ),
      ),
    ]);
  }
}

// --- left column: shares + bequests --------------------------------------
class _LeftColumn extends StatelessWidget {
  final Will will;
  final GlobalKey? heirsKey;
  const _LeftColumn({required this.will, this.heirsKey});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _AssetsLink(willId: will.id),
      const SizedBox(height: 16),
      const _LegacyLink(),
      const SizedBox(height: 16),
      const _DirectivesLink(),
      const SizedBox(height: 16),
      // The heirs anchor: what the dashboard's "Heir contacts" tile means by "heirs".
      KeyedSubtree(key: heirsKey, child: _SharesCard(shares: will.shariaShares)),
      const SizedBox(height: 16),
      _BequestsCard(will: will),
    ]);
  }
}

/// Cross-link to the directives (POA / healthcare) that live on the Wills page.
/// The prototype defined this copy (`directivesLink` + `manageLbl`) but never
/// wired it: from inside a will, point the owner back to where those separate,
/// effective-in-life documents are managed.
class _DirectivesLink extends StatelessWidget {
  const _DirectivesLink();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/wills'),
      child: _Card(
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.assignment_outlined, size: 19, color: context.tokens.goldInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.wlDocsExtraTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(context.l10n.wlDirectivesLink, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(context.l10n.wlManage,
              style: t.bodySmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 22, color: context.tokens.muted),
        ]),
      ),
    );
  }
}

/// Video & voice legacy messages live inside the will workflow (released with the
/// will), not as a separate top-level menu item.
class _LegacyLink extends StatelessWidget {
  const _LegacyLink();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/legacy'),
      child: _Card(
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.videocam_outlined, size: 19, color: WasiatiColors.bottleGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.wdLegacyTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(context.l10n.wdLegacySubtitle, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ]),
          ),
          WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 22, color: context.tokens.muted),
        ]),
      ),
    );
  }
}

class _AssetsLink extends StatelessWidget {
  final String willId;
  const _AssetsLink({required this.willId});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/wills/$willId/assets'),
      child: _Card(
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.inventory_2_outlined, size: 19, color: WasiatiColors.bottleGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.wdAssetsTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(context.l10n.wdAssetsSubtitle, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ]),
          ),
          WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 22, color: context.tokens.muted),
        ]),
      ),
    );
  }
}

class _SharesCard extends StatelessWidget {
  final List<ShariaShare> shares;
  const _SharesCard({required this.shares});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final total = shares.fold<double>(0, (a, s) => a + s.sharePercent);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionEyebrow(context, l.wdShariaShares),
        const SizedBox(height: 12),
        if (shares.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 14,
              child: Row(children: [
                for (var i = 0; i < shares.length; i++)
                  Expanded(
                    flex: (shares[i].sharePercent * 10).round().clamp(1, 100000),
                    child: Container(color: _seg(i)),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 15, child: _th(context, l.wdThHeir)),
          Expanded(flex: 14, child: _th(context, l.wdThBasis)),
          Expanded(flex: 7, child: _th(context, l.wdThShare, end: true)),
        ]),
        const SizedBox(height: 6),
        if (shares.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.wdNoHeirs, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          )
        else
          for (var i = 0; i < shares.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 15,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(width: 9, height: 9, decoration: BoxDecoration(color: _seg(i), borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${shares[i].heirName} — ${heirRelLabel(l, shares[i].heirRelation)}',
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  ]),
                ),
                // BASIS: the actual fiqh basis (Qur'an/Sunnah citation) from the backend,
                // falling back to the relation label if an older API doesn't send one.
                Expanded(
                  flex: 14,
                  child: Text(
                    shares[i].basisFor(Localizations.localeOf(context).languageCode) ??
                        heirRelLabel(l, shares[i].heirRelation),
                    style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.35),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Text('${_pct(shares[i].sharePercent)}%',
                      textAlign: TextAlign.end, style: t.titleSmall),
                ),
              ]),
            ),
        if (shares.isNotEmpty) ...[
          const Divider(height: 20),
          Row(children: [
            Text(l.wdTotalToHeirs, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            const Spacer(),
            Text('${_pct(total)}%', style: t.titleSmall),
          ]),
        ],
      ]),
    );
  }

  Widget _th(BuildContext context, String s, {bool end = false}) => Text(s,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.faint));
}

class _BequestsCard extends ConsumerWidget {
  final Will will;
  const _BequestsCard({required this.will});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final percent = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.wdAddBequestTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.l10n.wdBeneficiary)),
            const SizedBox(height: 10),
            TextField(
              controller: percent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: ctx.l10n.wdPercentOfEstate, helperText: ctx.l10n.wdFreeThirdHelper),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.l10n.commonAdd)),
          ],
        ),
      );
      if (ok != true || name.text.trim().isEmpty) return;
      try {
        await ref.read(willsApiProvider).addBequest(will.id,
            beneficiaryName: name.text.trim(), sharePercent: double.tryParse(percent.text) ?? 0);
        ref.invalidate(willProvider(will.id));
      } catch (e) {
        if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
      }
    } finally {
      name.dispose();
      percent.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final used = will.bequests.fold<double>(0, (a, b) => a + b.sharePercent);
    const cap = 33.33;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionEyebrow(context, l.rsBequestsTitle),
          const Spacer(),
          if (!will.locked)
            OutlinedButton.icon(onPressed: () => _add(context, ref), icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 16), label: Text(l.wdAddBequest)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text(context.digits(l.wdBequestUsed(_pct(used))), style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          const Spacer(),
          Text(l.wdBequestCap, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (used / cap).clamp(0, 1),
            minHeight: 10,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? WasiatiColors.nightSurface
                : WasiatiColors.parchmentDeep,
            valueColor: AlwaysStoppedAnimation(used > cap ? WasiatiColors.danger : WasiatiColors.brassGold),
          ),
        ),
        const SizedBox(height: 12),
        if (will.bequests.isEmpty)
          Text(l.wdNoBequests, style: t.bodySmall?.copyWith(color: context.tokens.muted))
        else
          for (final b in will.bequests)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.beneficiaryName, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (b.notes != null && b.notes!.isNotEmpty)
                      Text(b.notes!, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                  ]),
                ),
                Text('${_pct(b.sharePercent)}%', style: t.titleSmall),
              ]),
            ),
      ]),
    );
  }
}

// --- right column: people + message --------------------------------------
class _RightColumn extends StatelessWidget {
  final String willId;
  final Will will;
  final GlobalKey? witnessesKey;
  final GlobalKey? trusteesKey;
  const _RightColumn({required this.willId, required this.will, this.witnessesKey, this.trusteesKey});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      KeyedSubtree(
        key: witnessesKey,
        child: _PeopleSection(willId: willId, kind: PeopleKind.witnesses),
      ),
      const SizedBox(height: 16),
      KeyedSubtree(
        key: trusteesKey,
        child: _PeopleSection(willId: willId, kind: PeopleKind.trustees),
      ),
      const SizedBox(height: 16),
      _MessageCard(will: will),
      const SizedBox(height: 16),
      const _ReviewerNote(),
    ]);
  }
}

class _ReviewerNote extends StatelessWidget {
  const _ReviewerNote();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        context.l10n.wdReviewerNote,
        style: t.bodySmall?.copyWith(
            color: dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen, height: 1.5),
      ),
    );
  }
}

class _MessageCard extends ConsumerStatefulWidget {
  final Will will;
  const _MessageCard({required this.will});
  @override
  ConsumerState<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends ConsumerState<_MessageCard> {
  final TextEditingController _c = TextEditingController();
  bool _seeded = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    // The SAME classic wasiyya the create flow preloads on step 5.
    //
    // This is the other place a "message to my family" is written, and it opened blank —
    // so an owner who wrote their will here, or who came back to add the message later, met
    // an empty box on the hardest question in the product and never saw the template at all.
    // Preloading it in one of the two places it is asked for is not preloading it.
    //
    // Only ever fills an EMPTY message, so anything already written is untouched.
    final existing = widget.will.personalMessage ?? '';
    _c.text = existing.trim().isEmpty ? context.l10n.cwWordsDefault : existing;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final clean = sanitizePlainText(_c.text).trim();
    setState(() => _busy = true);
    try {
      await ref.read(willsApiProvider).saveMessage(widget.will.id, clean);
      ref.invalidate(willProvider(widget.will.id));
      if (mounted) WasiatiSnack.success(context, context.l10n.wdMessageSaved);
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return _Card(
      accentBorder: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Gold eyebrow to match the card's gold accent border (prototype).
        _sectionEyebrow(context, l.rsMessageTitle, color: context.tokens.goldInk),
        const SizedBox(height: 10),
        TextField(
          controller: _c,
          minLines: 3,
          maxLines: 6,
          maxLength: 5000, // spec §3 (DECISIONS §0)
          style: const TextStyle(fontStyle: FontStyle.italic),
          decoration: InputDecoration(
            hintText: l.wdMessageHint,
          ),
        ),
        Row(children: [
          Expanded(
            child: Text(l.wdMessagePartOfWill,
                style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.wdSaveMessage),
          ),
        ]),
      ]),
    );
  }
}

// --- witnesses / trustees ------------------------------------------------
enum PeopleKind { witnesses, trustees }

typedef _Person = ({String id, String name, String phone, String status});

class _PeopleSection extends ConsumerWidget {
  final String willId;
  final PeopleKind kind;
  const _PeopleSection({required this.willId, required this.kind});

  String _titleOf(AppLocalizations l) => kind == PeopleKind.witnesses ? l.wdWitnesses : l.wdTrustees;

  SealStatus _seal(String status) =>
      (status == 'SIGNED' || status == 'CONFIRMED') ? SealStatus.witnessed : SealStatus.idle;

  AsyncValue<List<_Person>> _watch(WidgetRef ref) {
    if (kind == PeopleKind.witnesses) {
      return ref
          .watch(witnessesProvider(willId))
          .whenData((l) => l.map((w) => (id: w.id, name: w.fullName, phone: w.phone, status: w.status)).toList());
    }
    return ref
        .watch(trusteesProvider(willId))
        .whenData((l) => l.map((t) => (id: t.id, name: t.fullName, phone: t.phone, status: t.status)).toList());
  }

  void _refresh(WidgetRef ref) => kind == PeopleKind.witnesses
      ? ref.invalidate(witnessesProvider(willId))
      : ref.invalidate(trusteesProvider(willId));

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    // The dialog owns its controllers (_AddPersonDialog) so they live exactly as
    // long as its route — disposing them here raced the exit transition.
    final person = await showDialog<({String name, String phone, String email})>(
      context: context,
      builder: (_) => _AddPersonDialog(
          title: kind == PeopleKind.witnesses ? context.l10n.wdAddWitnessTitle : context.l10n.wdAddTrusteeTitle),
    );
    if (person == null || person.name.length < 2) return;
    final api = ref.read(willsApiProvider);
    try {
      final ({String id, bool notified}) added;
      if (kind == PeopleKind.witnesses) {
        added = await api.addWitness(willId, fullName: person.name, phone: person.phone, email: person.email);
      } else {
        added = await api.addTrustee(willId, fullName: person.name, phone: person.phone, email: person.email);
      }
      // `notified: false` = the invite reached NOBODY (no SMS went out, no email
      // on file). Flag the row so the owner knows to contact them another way —
      // otherwise this person never confirms and the will never seals.
      if (!added.notified) {
        ref.read(rosterUnreachedProvider.notifier).update((s) => {...s, added.id});
      }
      _refresh(ref);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _sendCode(BuildContext context, WidgetRef ref, String id) async {
    final api = ref.read(willsApiProvider);
    // SMS is the only channel: these endpoints are unauthenticated and no longer echo
    // the code, so there is nothing to show the owner even in a dev build — and there
    // should not be, since an owner who could read it could self-confirm their own
    // witnesses.
    if (kind == PeopleKind.witnesses) {
      await api.sendWitnessCode(id);
    } else {
      await api.sendTrusteeCode(id);
    }
    if (!context.mounted) return;
    WasiatiSnack.success(context, context.l10n.wdCodeSentSms);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final data = _watch(ref);
    final unreached = ref.watch(rosterUnreachedProvider);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionEyebrow(context, _titleOf(l)),
        const SizedBox(height: 10),
        data.when(
          loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
          error: (e, _) => Text('$e', style: t.bodySmall),
          data: (list) => Column(children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l.wdNoneAddedYet, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                ),
              )
            else
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Seal(size: 30, status: _seal(p.status), filled: _seal(p.status) != SealStatus.idle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        // An invite that reached nobody replaces the status line with a
                        // calm "we couldn't reach them" — the row stays valid, the person
                        // just needs contacting another way (and only the owner can).
                        if (unreached.contains(p.id))
                          Text(l.wdInviteUnreached,
                              style: t.bodySmall?.copyWith(
                                  color: context.tokens.warningInk, fontWeight: FontWeight.w600, height: 1.35))
                        else
                          Text(_statusLine(l, p.status),
                              style: t.bodySmall?.copyWith(color: _statusColor(context, p.status), fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    // A confirmed witness has passed the national-ID name match (prototype).
                    if (kind == PeopleKind.witnesses && (p.status == 'SIGNED' || p.status == 'CONFIRMED')) ...[
                      const _IdMatchedPill(),
                      const SizedBox(width: 4),
                    ],
                    if (p.status == 'PENDING' || p.status == 'CODE_SENT')
                      FilledButton(
                        onPressed: () => _sendCode(context, ref, p.id),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        // "Send code" the first time; "Resend" only once a code has gone out.
                        child: Text(p.status == 'CODE_SENT' ? l.wdResend : l.wdSendCode),
                      ),
                  ]),
                ),
            OutlinedButton(
              onPressed: () => _add(context, ref),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
              child: Text(kind == PeopleKind.witnesses ? l.wdAddWitnessBtn : l.wdAddTrusteeBtn),
            ),
          ]),
        ),
      ]),
    );
  }

  String _statusLine(AppLocalizations l, String status) => switch (status) {
        'SIGNED' || 'CONFIRMED' => l.wdStatusConfirmed,
        'CODE_SENT' => l.wdStatusCodeSent,
        _ => l.wdStatusPending,
      };
  Color _statusColor(BuildContext context, String status) => switch (status) {
        'SIGNED' || 'CONFIRMED' => context.tokens.successInk,
        'CODE_SENT' => context.tokens.warningInk,
        _ => context.tokens.faint,
      };
}

/// Name + phone + optional email for a new witness/trustee. A StatefulWidget so
/// the TextEditingControllers are disposed by the dialog route's own lifecycle —
/// the caller disposing them raced the dialog's exit animation.
class _AddPersonDialog extends StatefulWidget {
  final String title;
  const _AddPersonDialog({required this.title});
  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: InputDecoration(labelText: l.wdFullName)),
        const SizedBox(height: 10),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: l.wdPhone)),
        const SizedBox(height: 10),
        // A second channel: when the SMS cannot be delivered the invite still
        // reaches them by email — without one, a bad number means silence.
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l.wdEmailOptional)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, (name: _name.text.trim(), phone: _phone.text.trim(), email: _email.text.trim())),
          child: Text(l.commonAdd),
        ),
      ],
    );
  }
}

// --- shared bits ---------------------------------------------------------
/// The prototype's section headings are uppercase, letter-spaced, muted eyebrows
/// (SHARES — FARA'ID, BEQUEST, WITNESSES & TRUSTEE, WORDS FOR MY FAMILY), not
/// sentence-case titles. One helper keeps every card consistent.
Widget _sectionEyebrow(BuildContext context, String label, {Color? color}) => Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: color ?? context.tokens.muted,
      ),
    );

/// Green "ID matched" pill — the witness's SMS name matched their national ID.
class _IdMatchedPill extends StatelessWidget {
  const _IdMatchedPill();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: WasiatiColors.success),
        ),
        child: Text(
          context.l10n.wdIdMatched.toUpperCase(),
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.successInk),
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final bool accentBorder;
  const _Card({required this.child, this.accentBorder = false});
  @override
  Widget build(BuildContext context) =>
      // A crisp 1px gold accent border (prototype), not the softer 40% hairline.
      WasiatiCard(borderColor: accentBorder ? context.tokens.gold : null, child: child);
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // The page's own back link lives in the `data:` branch, so this state had
            // none — a will that failed to load offered "Try again" and nothing else.
            WasiatiBackLink(
              label: context.l10n.wdBackToWills,
              onTap: () => context.go('/wills'),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.wdErrorLoadTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(context.l10n.wlTryAgain)),
          ]),
        ),
      );
}

const _palette = [
  WasiatiColors.bottleGreen,
  WasiatiColors.brassGold,
  WasiatiColors.goldSoft,
  WasiatiColors.greenSoft,
  WasiatiColors.info,
  WasiatiColors.warning,
];
Color _seg(int i) => _palette[i % _palette.length];
String _pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

