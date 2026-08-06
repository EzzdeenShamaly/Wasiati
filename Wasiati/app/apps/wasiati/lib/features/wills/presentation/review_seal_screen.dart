import 'widgets/verify_email_notice.dart';
import 'widgets/will_step_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/back_nav.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../application/wills_providers.dart';
import '../domain/wills_models.dart';
import '../../content/application/content_providers.dart';

/// Review & seal — step 3 (design 5d): read the will as the family will, then
/// seal it. Sealing calls the backend (which enforces the DRAFT→…→SEALED
/// lifecycle) and, on success, shows the celebration moment (10c).
class ReviewSealScreen extends ConsumerStatefulWidget {
  final String willId;
  const ReviewSealScreen({super.key, required this.willId});
  @override
  ConsumerState<ReviewSealScreen> createState() => _ReviewSealScreenState();
}

class _ReviewSealScreenState extends ConsumerState<ReviewSealScreen> {
  bool _reviewed = false;
  bool _busy = false;

  /// The backend enforces DRAFT → SIGNED (owner) → WITNESSED (witnesses) → SEALED.
  /// The single CTA advances the will through that lifecycle based on its status:
  /// a DRAFT will is first signed (the reviewed-and-confirmed acknowledgement IS the
  /// owner's digital signature, per spec §6 "Signed digitally"); only a WITNESSED will
  /// can be sealed. This closes the gap where the screen sealed a DRAFT and got a 400.
  Future<void> _advance(Will w) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(willsApiProvider);
      if (w.status == 'DRAFT') {
        await api.sign(widget.willId, signatureData: 'digital-acknowledgement');
        if (!mounted) return;
        ref.invalidate(willProvider(widget.willId));
        ref.invalidate(willsListProvider);
        // Now SIGNED; the screen re-renders into the "waiting for witnesses" state.
      } else if (w.status == 'WITNESSED') {
        await api.seal(widget.willId);
        if (!mounted) return;
        ref.invalidate(willProvider(widget.willId));
        ref.invalidate(willsListProvider);
        context.go('/wills/${widget.willId}/sealed');
      }
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final will = ref.watch(willProvider(widget.willId));
    final t = Theme.of(context).textTheme;
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: will.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // A failed load must not be a dead end. This branch used to render the raw
          // exception and nothing else — no back, no retry — on the screen that seals.
          error: (e, _) => _LoadFailed(
            message: '$e',
            willId: widget.willId,
            onRetry: () => ref.invalidate(willProvider(widget.willId)),
          ),
          data: (w) => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 860;
            final left = _ReviewList(will: w);
            // DRAFT requires the reviewed-and-confirm acknowledgement (the signature);
            // WITNESSED needs no checkbox (it's shown only pre-signature); SIGNED is a
            // disabled "waiting for witnesses" state handled inside the panel.
            final canAdvance = !_busy &&
                ((w.status == 'DRAFT' && _reviewed) || w.status == 'WITNESSED');
            final right = _SealPanel(
              will: w,
              reviewed: _reviewed,
              busy: _busy,
              onReviewed: (v) => setState(() => _reviewed = v),
              onAdvance: canAdvance ? () => _advance(w) : null,
            );
            return SingleChildScrollView(
              // The bar's height rides on the content, so the review sections and the seal
              // CTA slide under the glass mid-scroll and still come to rest clear of it.
              padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                  EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Breadcrumb back to the will being reviewed.
                    WasiatiBackLink(
                      label: context.l10n.commonBackToWill,
                      // Back to the STEP you came from. The wizard pushes this screen, so
                      // popping lands on step 5 with the form exactly as it was left.
                      onTap: () => context.goBack('/wills/${widget.willId}'),
                    ),
                    const SizedBox(height: 6),
                    // The same bar the wizard draws, complete. It used to stop existing on
                    // this screen: the owner watched it reach five of six across the guided
                    // steps and then lost it entirely on the step that finishes the flow.
                    const WillStepBar(step: kWillFlowSteps),
                    const SizedBox(height: 14),
                    Text(context.l10n.rsStep3,
                        style: TextStyle(
                            color: context.tokens.goldInk,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6)),
                    const SizedBox(height: 4),
                    Text(context.l10n.rsReadTitle, style: t.headlineSmall),
                    const SizedBox(height: 4),
                    Text(context.l10n.rsReadSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                    const SizedBox(height: 18),
                    if (wide)
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 14, child: left),
                          const SizedBox(width: 18),
                          Expanded(flex: 10, child: right),
                        ]),
                      )
                    else ...[left, const SizedBox(height: 16), right],
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

class _ReviewList extends StatelessWidget {
  final Will will;
  const _ReviewList({required this.will});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final shares = will.shariaShares;
    final bequestSummary = will.bequests.isEmpty
        ? l.rsBequestNone
        : will.bequests.map((b) => '${b.beneficiaryName} · ${_pct(b.sharePercent)}%').join('   ·   ');
    return Column(children: [
      _Section(
        title: l.rsHeirsTitle,
        editLabel: l.rsEditHeirs,
        onEdit: () => context.go('/wills/${will.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (shares.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 14,
                child: Row(children: [
                  for (var i = 0; i < shares.length; i++)
                    Expanded(flex: (shares[i].sharePercent * 10).round().clamp(1, 100000), child: Container(color: _seg(i))),
                ]),
              ),
            ),
          const SizedBox(height: 10),
          for (final s in shares)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${s.heirName} — ${heirRelLabel(l, s.heirRelation)}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Text('${_pct(s.sharePercent)}%', style: t.titleSmall),
              ]),
            ),
          if (shares.isEmpty) Text(l.rsNoHeirs, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        ]),
      ),
      const SizedBox(height: 12),
      _Section(
        title: l.rsBequestsTitle,
        editLabel: l.rsEditBequests,
        onEdit: () => context.go('/wills/${will.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bequestSummary, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
          const SizedBox(height: 4),
          Text(l.rsWithinCap, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        ]),
      ),
      const SizedBox(height: 12),
      _Section(
        title: l.rsMessageTitle,
        editLabel: l.rsEditMessage,
        onEdit: () => context.go('/wills/${will.id}'),
        child: Text(
          (will.personalMessage == null || will.personalMessage!.isEmpty)
              ? l.rsNoMessage
              : '“${will.personalMessage}”',
          style: t.bodySmall?.copyWith(color: context.tokens.muted, fontStyle: FontStyle.italic, height: 1.6),
        ),
      ),
      const SizedBox(height: 12),
      _WitnessSummary(willId: will.id),
      // Guardianship. Shown only when one was chosen, because it is only asked of
      // owners with minor children. The generated document now renders the same choice
      // under the SAME condition (guardianOf in will-document.service.ts), so this is a
      // faithful preview of the sealed will, not the only place the choice is read back.
      // Keep the two gates in step — if this shows a guardian, the PDF must name one.
      if ((will.guardianMode ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        _Section(
          title: l.rsGuardianTitle,
          editLabel: l.rsEditPeople,
          onEdit: () => context.go('/wills/new/form'),
          child: Text(
            switch (will.guardianMode) {
              'islamic' => l.cwGIslamicLbl,
              'named' => (will.guardianName ?? '').trim().isEmpty ? l.cwGNamedLbl : will.guardianName!.trim(),
              _ => l.cwGParentLbl,
            },
            style: t.bodyMedium?.copyWith(color: context.tokens.muted),
          ),
        ),
      ],
    ]);
  }
}

class _WitnessSummary extends ConsumerWidget {
  final String willId;
  const _WitnessSummary({required this.willId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final witnesses = ref.watch(witnessesProvider(willId));
    final trustees = ref.watch(trusteesProvider(willId));
    final muted = context.tokens.muted;
    final base = t.bodyMedium?.copyWith(color: muted);

    // Status is a bundled Material icon, not a Unicode ✓/⋯ — those glyphs are
    // absent from the app fonts and would render as tofu on locked-down devices.
    final spans = <InlineSpan>[TextSpan(text: '${l.rsWitnessesInline} ')];
    witnesses.maybeWhen(
      data: (list) {
        if (list.isEmpty) {
          spans.add(TextSpan(text: l.rsNoneAdded));
        } else {
          for (var i = 0; i < list.length; i++) {
            if (i > 0) spans.add(const TextSpan(text: '   ·   '));
            final signed = _signed(list[i].status);
            spans.add(TextSpan(text: '${list[i].fullName} '));
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(signed ? Icons.check_rounded : Icons.more_horiz,
                  size: 15, color: signed ? context.tokens.successInk : context.tokens.faint),
            ));
          }
        }
      },
      orElse: () => spans.add(const TextSpan(text: '…')),
    );
    final tLine = trustees.maybeWhen(
      data: (list) => list.isEmpty ? l.rsNoneAdded : [for (final tr in list) tr.fullName].join(' · '),
      orElse: () => '…',
    );
    spans.add(TextSpan(text: '   ·   ${l.rsTrusteeInline} $tLine ${l.rsCodeSentSuffix}'));

    return _Section(
      title: l.rsPeopleTitle,
      editLabel: l.rsEditPeople,
      onEdit: () => context.go('/wills/$willId'),
      child: Text.rich(TextSpan(style: base, children: spans)),
    );
  }

  bool _signed(String s) => s == 'SIGNED' || s == 'CONFIRMED';
}

class _Section extends StatelessWidget {
  final String title;
  final String editLabel;
  final VoidCallback onEdit;
  final Widget child;
  const _Section({required this.title, required this.editLabel, required this.onEdit, required this.child});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(onPressed: onEdit, child: Text(editLabel)),
        ]),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

/// The will could not be loaded — say so, offer a retry, and always offer the way out.
///
/// The error branch used to be `Center(child: Text('$e'))`: a raw exception on the screen
/// that seals a will, with no back control anywhere on it, because the only WasiatiBackLink
/// lives in the `data:` branch. A transient 500 stranded the owner completely.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.willId, required this.onRetry});
  final String message;
  final String willId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        WasiatiBackLink(label: l.commonBackToWill, onTap: () => context.goBack('/wills/$willId')),
        const SizedBox(height: 20),
        Icon(Icons.error_outline, size: 28, color: context.tokens.warningInk),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onRetry, child: Text(l.wlTryAgain)),
      ]),
    );
  }
}

/// "Read the full document" — the way from the review step to the document page.
///
/// Replaces a Flutter-drawn mock of a will (a seal, a heading and four grey bars) that
/// pretended to be a preview and could never be read. An honest link to the real thing is
/// worth more than a picture of one, and it keeps a single place where the document lives.
class _ReadDocumentLink extends StatelessWidget {
  const _ReadDocumentLink({required this.willId});
  final String willId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return WasiatiCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      onTap: () => context.go('/wills/$willId/document'),
      child: Row(children: [
        const Seal(size: 30, status: SealStatus.idle),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.rsLastWill, style: t.titleSmall),
            const SizedBox(height: 2),
            Text(l.rsFullText, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4)),
          ]),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right, size: 20, color: context.tokens.muted),
      ]),
    );
  }
}

class _SealPanel extends ConsumerWidget {
  final Will will;
  final bool reviewed;
  final bool busy;
  final ValueChanged<bool> onReviewed;
  final VoidCallback? onAdvance;
  const _SealPanel(
      {required this.will,
      required this.reviewed,
      required this.busy,
      required this.onReviewed,
      required this.onAdvance});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isDraft = will.status == 'DRAFT';
    final isWitnessed = will.status == 'WITNESSED';
    final isSigned = will.status == 'SIGNED';
    // Witness signing progress (for the "waiting" note after the owner has signed).
    final witnesses = ref.watch(witnessesProvider(will.id));
    final total = witnesses.maybeWhen(data: (l) => l.length, orElse: () => 0);
    final signed = witnesses.maybeWhen(
        data: (l) => l.where((w) => w.status == 'SIGNED').length, orElse: () => 0);
    // Fresh from /users/me, not the cached session user — the link is usually
    // clicked in another tab. Default true while loading/on error: the banner is
    // an entry point, not the gate; the backend still refuses an unverified seal.
    final emailVerified =
        ref.watch(emailVerifiedProvider).maybeWhen(data: (v) => v, orElse: () => true);
    return Column(children: [
      if (!emailVerified) ...[
        VerifyEmailNotice(onReturn: () => ref.invalidate(emailVerifiedProvider)),
        const SizedBox(height: 14),
      ],
      // The Flutter-drawn document MOCK that used to sit here — a seal, the words "Last
      // will", four grey bars standing in for text — is gone. It shared this ~420px column
      // with the real server-rendered preview directly beneath it, so the screen showed two
      // things that looked like the will, one of them decorative, and the real one too
      // narrow to read. The document now has its own full-width page (willDoc), linked
      // below, which is where the prototype puts it too.
      _ReadDocumentLink(willId: will.id),
      const SizedBox(height: 14),
      // seal box
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WasiatiColors.goldBorderStrong),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // The reviewed-and-confirm acknowledgement (= the digital signature) is only
          // shown while the will is still a DRAFT awaiting the owner's signature.
          if (isDraft) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(value: reviewed, onChanged: (v) => onReviewed(v ?? false), activeColor: WasiatiColors.bottleGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                // Admin-overridable. This is the legal disclaimer the owner ticks to seal,
                // and the exact string ContentService advertises as correctable without an
                // app release. The wiring lived on the create wizard's review step; when
                // sealing moved here it had to come with it, or an admin could edit the one
                // string where being out of date is a legal problem, be told it saved, and
                // watch the old text keep rendering.
                child: Text(
                  overrideText(ref, key: 'rsReviewedConfirm', fallback: l.rsReviewedConfirm, isRtl: context.isRtl),
                  style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5),
                ),
              ),
            ]),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            // DRAFT -> sign, WITNESSED -> seal, SIGNED -> disabled (waiting on witnesses).
            onPressed: isSigned ? null : onAdvance,
            style: WasiatiButtons.goldSolid(context),
            icon: busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.onDark))
                : Icon(isWitnessed ? Icons.lock : (isSigned ? Icons.hourglass_top : Icons.edit_outlined), size: 17),
            label: Text(isWitnessed
                ? l.rsSealMyWill
                : (isSigned ? l.rsWaitingWitnesses : l.rsSignMyWill)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              isSigned
                  // "0 of 0 signed" reads as nothing-outstanding; when no witnesses were
                  // added yet, tell the owner to add them (the recovery path) instead.
                  ? (total == 0
                      ? l.rsSignedNoWitnesses
                      : context.digits(l.rsSignedWaitingNote(signed.toString(), total.toString())))
                  : (isWitnessed ? l.rsWitnessCodesNote : l.rsSignNote),
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 10.5),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Sealing REQUIRES a confirmed email (fdb4c3e) — this is the in-app way to fix
/// it. Without it, an unverified owner reaching the seal step got the backend's
/// 400 in a snackbar and a dead end: /verify-email's resend form existed but
/// NOTHING in the app navigated to it.
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
