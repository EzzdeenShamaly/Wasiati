import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../commerce/application/commerce_providers.dart' show creditHistoryProvider;
import '../../commerce/domain/commerce_models.dart' show CreditEntry, formatMoney;
import '../application/referrals_providers.dart';
import '../domain/referral_models.dart';

/// Invite a friend: your code, the share link, and what you have earned.
///
/// Two credit figures are shown SEPARATELY and never summed into one headline —
/// commission is held for 100 days before it can be spent, and a single "balance"
/// would promise money the user cannot yet use.
class ReferralsScreen extends ConsumerWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final summary = ref.watch(referralSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.refTitle)),
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // The bar's height rides on the content, so the earnings card slides under the
          // glass mid-scroll and still comes to rest clear of it.
          padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: summary.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _Card(
                  child: Text(
                    e is ApiException ? e.message : l.refLoadError,
                    style: t.bodyMedium,
                  ),
                ),
                data: (s) => _Body(summary: s),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary});
  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    String money(int minor) => formatMoney(minor, summary.currency);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.refSubtitle, style: t.bodyLarge?.copyWith(color: context.tokens.muted, height: 1.5)),
      const SizedBox(height: 18),

      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.refYourCode, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          const SizedBox(height: 6),
          SelectableText(
            summary.code,
            style: t.headlineMedium?.copyWith(letterSpacing: 3, color: context.tokens.gold),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SelectableText(
                summary.shareUrl,
                maxLines: 1,
                style: t.bodySmall?.copyWith(color: context.tokens.muted),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(l.refCopyLink),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: summary.shareUrl));
                if (context.mounted) WasiatiSnack.success(context, l.refCopied);
              },
            ),
          ]),
          const SizedBox(height: 10),
          Text(l.refTerms, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4)),
        ]),
      ),
      const SizedBox(height: 14),

      // Spendable vs held — deliberately two numbers, not one.
      Row(children: [
        Expanded(
          child: _Stat(
            label: l.refCreditAvailable,
            value: money(summary.creditSpendableMinor),
            emphasis: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _Stat(label: l.refCreditHeld, value: money(summary.creditHeldMinor))),
      ]),
      if (summary.creditHeldMinor > 0) ...[
        const SizedBox(height: 8),
        Text(
          context.digits(l.refCreditHeldNote(summary.holdDays)),
          style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4),
        ),
      ],
      const SizedBox(height: 14),

      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _Mini(label: l.refInvited, value: '${summary.invited}')),
            Expanded(child: _Mini(label: l.refRewarded, value: '${summary.rewarded}')),
            if (summary.capped > 0) Expanded(child: _Mini(label: l.refCapped, value: '${summary.capped}')),
          ]),
          const SizedBox(height: 16),
          Text(l.refEarnedThisYear, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(money(summary.earnedThisYearMinor), style: t.titleLarge),
            const SizedBox(width: 6),
            Text(
              context.digits(l.refYearlyCap(money(summary.yearlyCapMinor))),
              style: t.bodySmall?.copyWith(color: context.tokens.muted),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: summary.yearlyCapMinor == 0
                  ? 0
                  : (summary.earnedThisYearMinor / summary.yearlyCapMinor).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: context.tokens.raised,
              valueColor: AlwaysStoppedAnimation(
                summary.capReached ? WasiatiColors.warning : context.tokens.gold,
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      const _HistoryCard(),
    ]);
  }
}

/// The credit ledger (`GET /credits/history`): every grant and every spend, so
/// the two balances above are explainable rather than just numbers. Without
/// this the screen showed a figure with no way to see where it came from.
class _HistoryCard extends ConsumerWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final history = ref.watch(creditHistoryProvider);
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.refHistoryTitle, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        const SizedBox(height: 8),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text(
            e is ApiException ? e.message : l.refHistoryError,
            style: t.bodySmall?.copyWith(color: context.tokens.muted),
          ),
          data: (entries) => entries.isEmpty
              ? Text(l.refHistoryEmpty, style: t.bodySmall?.copyWith(color: context.tokens.muted))
              : Column(children: [for (final e in entries) _HistoryRow(entry: e)]),
        ),
      ]),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final CreditEntry entry;

  /// The reason enum, localized. An unknown reason (newer server) falls back to
  /// the server's own description rather than a blank row.
  String _reasonLabel(AppLocalizations l) => switch (entry.reason) {
        'REFERRAL_REWARD' => l.refHistoryReasonReferral,
        'PURCHASE_APPLIED' => l.refHistoryReasonPurchase,
        'MANUAL_ADJUSTMENT' => l.refHistoryReasonAdjustment,
        'REFUND' => l.refHistoryReasonRefund,
        _ => entry.description ?? entry.reason,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final locale = l.localeName;
    final held = entry.isHeldAt(DateTime.now());
    final positive = entry.amountMinor >= 0;
    final sub = [
      if (entry.createdAt != null) DateFormat.yMMMd(locale).format(entry.createdAt!.toLocal()),
      // Held commission says when it becomes spendable, matching the note above.
      if (held) l.refHistorySpendable(DateFormat.yMMMd(locale).format(entry.maturesAt!.toLocal())),
    ].join(' · ');
    final amount = '${positive ? '+' : '-'}${formatMoney(entry.amountMinor.abs(), entry.currency)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_reasonLabel(l), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty)
              Text(context.digits(sub), style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(
          context.digits(amount),
          style: t.titleSmall?.copyWith(
            // Held money is visually muted — earned, but not promising anything yet.
            color: held ? context.tokens.faint : (positive ? context.tokens.successInk : null),
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        const SizedBox(height: 6),
        Text(
          value,
          style: t.titleLarge?.copyWith(color: emphasis ? context.tokens.goldInk : null),
        ),
      ]),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: t.titleLarge),
      Text(label, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => WasiatiCard(child: child);
}
