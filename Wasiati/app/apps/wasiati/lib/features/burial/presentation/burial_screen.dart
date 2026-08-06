import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/domain/auth_state.dart';
import '../../../core/providers.dart';
import '../application/burial_providers.dart';
import '../domain/burial_models.dart';

/// Burial planning (design 10a, Ultimate · US/CA).
///
/// SHIPS AS AN ESTIMATE ONLY. The screen prices a grave at today's cost and shows what
/// equal contributions would come to per month — no interest, no profit, no inflation
/// (docs/DECISIONS.md §6). It does NOT collect anything: [_save] writes a
/// BurialEstimateRequest, and the only code that creates a BurialPrepaymentPlan sits
/// behind an ADMIN route with no client caller, so no charge is ever made.
///
/// The copy is therefore CONDITIONAL throughout ("would be per month", "when prepayment
/// opens"). It previously read as though a plan were funding — "YOUR PREPAID PLAN",
/// "Added to subscription $X/mo", "Plan saved.", and escrow terms in the present tense —
/// which told users money was being held for them when none had been taken. If the
/// prepayment path is ever wired up, move this copy back to the present tense in the
/// SAME commit, not before.
class BurialScreen extends ConsumerStatefulWidget {
  const BurialScreen({super.key});
  @override
  ConsumerState<BurialScreen> createState() => _BurialScreenState();
}

class _BurialScreenState extends ConsumerState<BurialScreen> {
  final _city = TextEditingController();
  final _amount = TextEditingController(text: '9500');
  late String _currency;
  int _years = 5;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _currency = (auth is AuthSignedIn && auth.user.region == 'CA') ? 'CAD' : 'USD';
  }

  @override
  void dispose() {
    _city.dispose();
    _amount.dispose();
    super.dispose();
  }

  double get _cost => double.tryParse(_amount.text) ?? 0;
  int get _months => _years * 12;
  double get _monthly => _months == 0 ? 0 : _cost / _months;
  String _money(double v) => _currency == 'CAD' ? 'CA\$${v.toStringAsFixed(0)}' : '\$${v.toStringAsFixed(0)}';

  Future<void> _save() async {
    if (_city.text.trim().isEmpty || _cost <= 0) {
      WasiatiSnack.danger(context, context.l10n.burialEnterCityCost);
      return;
    }
    setState(() => _busy = true);
    try {
      // No inflation: projectedAmount == today's cost, split into equal contributions.
      await ref.read(burialApiProvider).create(
            city: _city.text.trim(),
            baseAmount: _cost,
            currency: _currency,
            inflationRatePercent: 0,
            projectionYears: _years,
          );
      ref.invalidate(burialListProvider);
      if (mounted) WasiatiSnack.success(context, context.l10n.burialPlanSaved);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimates = ref.watch(burialListProvider);
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 820;
          final inputs = _inputs(context);
          final plan = _plan(context);
          return SingleChildScrollView(
            // The bar's height rides on the content, so the plan card slides under the
            // glass mid-scroll and the last card still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (wide)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(flex: 10, child: inputs),
                        const SizedBox(width: 18),
                        Expanded(flex: 12, child: plan),
                      ]),
                    )
                  else ...[inputs, const SizedBox(height: 16), plan],
                  const SizedBox(height: 22),
                  estimates.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => _errorOrUpgrade(context, e),
                    data: (list) => list.isEmpty
                        ? const SizedBox.shrink()
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(context.l10n.burialSavedPlans, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            for (final est in list) _EstimateCard(est: est),
                          ]),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _inputs(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.burialTitle, style: t.headlineSmall),
        const SizedBox(height: 4),
        Text(l.burialSubtitle,
            style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 16),
        _label(context, l.burialCity),
        TextField(controller: _city, decoration: InputDecoration(hintText: l.burialCityHint), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        _label(context, l.burialCostToday),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: _currency == 'CAD' ? 'CA\$ ' : '\$ '),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _currency,
              items: const [DropdownMenuItem(value: 'USD', child: Text('USD')), DropdownMenuItem(value: 'CAD', child: Text('CAD'))],
              onChanged: (v) => setState(() => _currency = v ?? 'USD'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _label(context, l.burialContributionPeriod),
        Row(children: [
          for (final y in const [3, 5, 10]) ...[
            Expanded(child: _periodTab(context, y)),
            if (y != 10) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 6),
        Text(l.burialMaxPeriod, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.burialSavePlan),
          ),
        ),
        const SizedBox(height: 10),
        Text(l.burialCovers,
            style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
      ]),
    );
  }

  Widget _periodTab(BuildContext context, int y) {
    final selected = _years == y;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() => _years = y),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? WasiatiColors.bottleGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? WasiatiColors.bottleGreen : context.tokens.hairline),
        ),
        child: Text(context.digits(context.l10n.burialYearsShort(y)),
            style: TextStyle(
                color: selected ? WasiatiColors.onDark : (Theme.of(context).brightness == Brightness.dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen),
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }

  Widget _plan(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fundedBy = DateTime.now().year + _years;
    final city = _city.text.trim();
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(city.isEmpty ? l.burialPlanHeader : l.burialPlanHeaderCity(city.toUpperCase()),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: context.tokens.muted)),
        const SizedBox(height: 8),
        // This card used to read "YOUR PREPAID PLAN" beside a live "$X /mo" figure and a
        // rising funding chart, and saving it said "Plan saved." Nothing of the sort
        // happened: _save() writes a BurialEstimateRequest, and the ONLY code that creates
        // a BurialPrepaymentPlan is behind an ADMIN route with no client caller — so no
        // charge was ever made and amountPaid stayed 0 forever. A user could believe for
        // years they were prepaying for a grave. The chip states the truth up front rather
        // than leaving it to the terms paragraph below.
        _EstimateOnlyChip(label: l.burialEstimateOnlyNote),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _stat(context, l.burialCostToday, _money(_cost), false)),
          const SizedBox(width: 12),
          Expanded(child: _stat(context, l.burialAddedToSub, context.digits(l.burialPerMonth(_money(_monthly))), true)),
          const SizedBox(width: 12),
          Expanded(child: _stat(context, l.burialFundedBy, '$fundedBy', false)),
        ]),
        const SizedBox(height: 16),
        const _CumulativeBar(),
        const SizedBox(height: 8),
        Text(context.digits(l.burialContributionSummary(_months, _money(_cost))),
            style: t.bodySmall?.copyWith(color: context.tokens.faint)),
        const SizedBox(height: 10),
        // The escrow terms (own money, refundable, family settles the balance) are what
        // would make this prepayment rather than credit or preneed insurance — so they
        // belong on-screen, not in a policy page. But they are written in the
        // CONDITIONAL until prepayment actually exists: stating them in the present
        // tense described money we never took.
        Text(l.burialTerms, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WasiatiColors.goldBorder),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.burialWantRealNumber, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(l.burialQuoteDesc,
                    style: t.bodySmall?.copyWith(color: context.tokens.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: WasiatiButtons.goldSolid(context).copyWith(
                minimumSize: WidgetStateProperty.all(const Size(0, 40)),
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
              ),
              child: Text(l.burialRequestQuote),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, String value, bool highlight) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? WasiatiColors.bottleGreen : (dark ? WasiatiColors.nightSurface : WasiatiColors.parchment),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall?.copyWith(color: highlight ? WasiatiColors.darkTextMuted : context.tokens.muted, fontSize: 11)),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(value,
              style: t.titleLarge?.copyWith(color: highlight ? WasiatiColors.goldSoft : null, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _label(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted, fontWeight: FontWeight.w600)),
      );

  Widget _errorOrUpgrade(BuildContext context, Object e) {
    if (!isPaywall(e)) return Text('$e', style: Theme.of(context).textTheme.bodySmall);
    return WasiatiUpgradePrompt(
      seal: SealStatus.locked,
      title: context.l10n.burialUltimatePlan,
      body: context.l10n.burialUltimateDesc,
      seePlansLabel: context.l10n.commonSeePlans,
      onSeePlans: () => context.go('/pricing'),
    );
  }
}

class _CumulativeBar extends StatelessWidget {
  const _CumulativeBar();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const heights = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
    return SizedBox(
      height: 120,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < heights.length; i++) ...[
          Expanded(
            child: FractionallySizedBox(
              heightFactor: heights[i],
              child: Container(
                decoration: BoxDecoration(
                  color: i == heights.length - 1
                      ? WasiatiColors.brassGold
                      : Color.lerp(dark ? WasiatiColors.nightSurface : WasiatiColors.greenTint, WasiatiColors.bottleGreen, heights[i]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ),
            ),
          ),
          if (i != heights.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

class _EstimateCard extends ConsumerWidget {
  final BurialEstimate est;
  const _EstimateCard({required this.est});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final months = est.projectionYears * 12;
    final monthly = months == 0 ? 0.0 : est.baseAmount / months;
    return _Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(est.city, style: t.titleMedium)),
          Text(context.digits(l.burialPerMonth(est.money(monthly))), style: t.titleMedium?.copyWith(color: context.tokens.goldInk)),
        ]),
        const SizedBox(height: 4),
        Text(context.digits(l.burialEstimateSummary(est.money(est.baseAmount), months)),
            style: t.bodySmall?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 8),
        if (est.status == 'QUOTED' && est.manualQuoteAmount != null)
          Text(
              est.manualQuoteNotes != null
                  ? context.digits(l.burialProviderQuoteNotes(est.money(est.manualQuoteAmount!), est.manualQuoteNotes!))
                  : context.digits(l.burialProviderQuote(est.money(est.manualQuoteAmount!))),
              style: t.bodyMedium?.copyWith(color: context.tokens.goldInk))
        else if (est.status == 'QUOTE_REQUESTED')
          Text(l.burialQuoteRequested, style: t.bodySmall?.copyWith(color: context.tokens.muted))
        else
          OutlinedButton(
            onPressed: () async {
              await ref.read(burialApiProvider).requestQuote(est.id);
              ref.invalidate(burialListProvider);
            },
            child: Text(l.burialRequestRealQuote),
          ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  const _Card({required this.child, this.margin = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) => WasiatiCard(margin: margin, child: child);
}


/// States plainly that no money is involved yet.
///
/// Deliberately a filled chip rather than muted body text: the figures beside it are
/// large and concrete, and a quiet disclaimer under them loses to the numbers. A reader
/// who takes in only the headline and this chip should still come away correct.
class _EstimateOnlyChip extends StatelessWidget {
  final String label;
  const _EstimateOnlyChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final gold = WasiatiColors.goldDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        // 0.08, not 0.12: this chip paints gold type on a wash of its OWN colour, and at
        // 12% the label lands at 4.35:1 — under AA for a 12px disclaimer the file itself
        // calls load-bearing. Thinning the wash lifts it to 4.58:1 without touching the
        // shared gold, which has other jobs.
        color: gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: gold.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: gold, fontWeight: FontWeight.w600),
      ),
    );
  }
}
