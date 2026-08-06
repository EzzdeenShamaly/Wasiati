import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Only the formatter: intl also exports a TextDirection that shadows dart:ui's.
import 'package:intl/intl.dart' show DateFormat;
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/safe_launch.dart';
import '../application/death_claims_providers.dart';
import '../domain/death_claim_models.dart';

// Content-width action buttons (the theme defaults to full width, which can't
// live inside a Wrap/Row).
final ButtonStyle _compact = OutlinedButton.styleFrom(minimumSize: const Size(0, 44));
final ButtonStyle _compactFilled = FilledButton.styleFrom(minimumSize: const Size(0, 44));

/// Admin queue for death claims (design 8c): review, approve (sends the safety
/// check), reject with a reason, and release once approved + a trustee confirms.
class DeathClaimsAdminScreen extends ConsumerWidget {
  const DeathClaimsAdminScreen({super.key});

  Future<void> _do(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(pendingClaimsProvider);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final claims = ref.watch(pendingClaimsProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: claims.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => ListView(
                // The bar's height rides on the content, so claim cards slide under the glass
                // mid-scroll and the last one still comes to rest clear of it.
                padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                children: [
                  Row(children: [
                    const Seal(size: 32, status: SealStatus.verified),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.dcEyebrow,
                            style: TextStyle(color: context.tokens.goldInk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                        Text(l.dcTitle, style: t.headlineSmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(l.dcCareNote, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text(l.dcNoPending, style: t.bodyLarge?.copyWith(color: context.tokens.muted))),
                    )
                  else
                    for (final c in list) _ClaimCard(claim: c, onAction: _do, ref: ref),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClaimCard extends StatefulWidget {
  final DeathClaim claim;
  final WidgetRef ref;
  final Future<void> Function(BuildContext, WidgetRef, Future<void> Function()) onAction;
  const _ClaimCard({required this.claim, required this.onAction, required this.ref});
  @override
  State<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends State<_ClaimCard> {
  bool _rejecting = false;
  bool _openingCertificate = false;
  final _reason = TextEditingController();

  DeathClaim get claim => widget.claim;

  /// Opens the death certificate this claim was filed on.
  ///
  /// This card used to print a static "Certificate on file" label and stop there, and the
  /// URL the claim carries could not have been opened anyway: it points at the owner-scoped
  /// /files/:id/download, and the file belongs to the deceased. So the reviewer approved —
  /// starting a 72h window that ends in an estate being handed over — without ever seeing
  /// the document the whole check is built around. The server now has an admin-scoped route
  /// that presigns it; this is the button that uses it.
  Future<void> _openCertificate() async {
    if (_openingCertificate) return; // a second tap would mint a second signed URL
    setState(() => _openingCertificate = true);
    try {
      final url = await widget.ref.read(deathClaimsApiProvider).certificateUrl(claim.id);
      // Through the same https-only guard as every other server-supplied URL.
      final ok = await safeLaunchExternal(url);
      if (!ok && mounted) WasiatiSnack.danger(context, context.l10n.dcCertificateOpenFailed);
    } catch (e) {
      // Includes the backend's "no resolvable certificate — do not approve without
      // obtaining the document out of band", which is exactly what the reviewer needs.
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _openingCertificate = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Inks, not the raw fills: this drives the status dot AND its label, which read as
  /// one mark. A raw dot beside ink type would show two shades of the same state, and
  /// at 2.03:1 on a night card the dot misses even the 3:1 bar for a graphical object.
  Color _statusColor(BuildContext context, String status) => switch (status) {
        'UNDER_REVIEW' => context.tokens.warningInk,
        'APPROVED' => context.tokens.successInk,
        'RELEASED' => context.tokens.successInk,
        'REJECTED' => context.tokens.dangerInk,
        _ => context.tokens.infoInk, // SUBMITTED
      };

  /// Everything still standing between this claim and release, in the server's terms.
  ///
  /// Ready is one line, not a list of ticks: an operator scanning a queue needs "yes" or
  /// "what is missing", and a wall of green adds nothing.
  List<String> _gateLines(AppLocalizations l, ReleaseGate g) {
    if (g.ready) return [l.dcGateReadyNote];
    return [
      if (!g.safetyWindowElapsed && g.releasableAt != null)
        l.dcGateWindow(DateFormat.yMMMMd(l.localeName).add_Hm().format(g.releasableAt!.toLocal())),
      if (!g.willSealed) l.dcGateNotSealed,
      if (!g.trusteeConfirmed) l.dcGateNoTrustee,
      if (!g.heirsSatisfied) l.dcGateWaitingHeirs(g.outstandingHeirConfirmations),
      // Worth saying even when everything else blocks: it explains why the heir line is
      // absent on a claim whose heirs plainly have not answered.
      if (g.overrideActive) l.dcGateOverride,
    ];
  }

  String _statusLabel(AppLocalizations l, String status) => switch (status) {
        'SUBMITTED' => l.dcStatusSubmitted,
        'UNDER_REVIEW' => l.dcStatusUnderReview,
        'APPROVED' => l.dcStatusApproved,
        'RELEASED' => l.dcStatusReleased,
        'REJECTED' => l.dcStatusRejected,
        _ => status.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final api = widget.ref.read(deathClaimsApiProvider);
    final stColor = _statusColor(context, claim.status);
    final reasonOk = _reason.text.trim().length >= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Seal(size: 34, status: switch (claim.status) {
            'APPROVED' => SealStatus.witnessed,
            'RELEASED' => SealStatus.verified,
            _ => SealStatus.locked,
          }),
          const SizedBox(width: 12),
          Expanded(child: Text(claim.submittedByName, style: t.titleMedium)),
          // Status dot + label (prototype 8c) instead of a chip pill.
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: stColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_statusLabel(l, claim.status),
                style: t.labelSmall?.copyWith(color: stColor, fontWeight: FontWeight.w700)),
          ]),
        ]),
        const SizedBox(height: 8),
        Text(
            claim.ownerEmail != null
                ? l.dcSubmittedByFor(claim.submittedByPhone, claim.ownerEmail!)
                : l.dcSubmittedBy(claim.submittedByPhone),
            style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        if (claim.certificateFileUrl != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openingCertificate ? null : _openCertificate,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: _openingCertificate
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.description_outlined, size: 15),
              label: Text(l.dcViewCertificate, style: t.bodySmall),
            ),
          ),
        ],
        if (_rejecting) ...[
          const SizedBox(height: 14),
          // Inline danger panel (prototype 8c): Confirm disabled until a reason is typed.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WasiatiColors.danger),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.dcRejectReasonRequired,
                  style: t.labelMedium?.copyWith(color: context.tokens.dangerInk, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: l.dcReason),
              ),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: WasiatiColors.danger,
                    disabledBackgroundColor: WasiatiColors.danger.withValues(alpha: 0.4),
                    foregroundColor: WasiatiColors.onDark,
                  ),
                  onPressed: reasonOk
                      ? () async {
                          await widget.onAction(
                              context, widget.ref, () => api.reject(claim.id, _reason.text.trim()));
                          if (mounted) setState(() => _rejecting = false);
                        }
                      : null,
                  child: Text(l.dcReject),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _rejecting = false), child: Text(l.commonCancel)),
              ]),
            ]),
          ),
        ] else ...[
          // WHY the Release button is where it is. Counts and conditions only — the server
          // no longer sends heir names, because a private will's roster is not an
          // operator's to read.
          if (claim.releaseGate != null) ...[
            const SizedBox(height: 10),
            for (final line in _gateLines(l, claim.releaseGate!))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    claim.releaseGate!.ready ? Icons.check_circle_outline : Icons.schedule,
                    size: 14,
                    color: claim.releaseGate!.ready ? context.tokens.successInk : context.tokens.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(line, style: t.bodySmall?.copyWith(color: context.tokens.muted))),
                ]),
              ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (claim.status == 'SUBMITTED')
              OutlinedButton(style: _compact, onPressed: () => widget.onAction(context, widget.ref, () => api.underReview(claim.id)), child: Text(l.dcStartReview)),
            if (claim.status == 'SUBMITTED' || claim.status == 'UNDER_REVIEW')
              FilledButton(style: _compactFilled, onPressed: () => widget.onAction(context, widget.ref, () => api.approve(claim.id)), child: Text(l.dcApprove)),
            // Gated on the server's OWN answer. The gate travels with every APPROVED claim
            // for exactly this purpose and was being discarded, so the button was always
            // live and an admin found out by pressing it — then pressed it again the next
            // day to poll, because nothing on screen said when it would open.
            if (claim.status == 'APPROVED')
              FilledButton(
                style: _compactFilled.copyWith(backgroundColor: WidgetStateProperty.all(WasiatiColors.goldDeep)),
                onPressed: claim.releaseGate?.ready == false
                    ? null
                    : () => widget.onAction(context, widget.ref, () => api.release(claim.id)),
                child: Text(l.dcRelease),
              ),
            if (claim.status != 'RELEASED' && claim.status != 'REJECTED')
              TextButton(
                style: TextButton.styleFrom(foregroundColor: context.tokens.dangerInk),
                onPressed: () => setState(() => _rejecting = true),
                child: Text(l.dcReject),
              ),
          ]),
        ],
      ]),
    );
  }
}

