import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/network/safe_launch.dart';
import '../../auth/domain/auth_state.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/config/env.dart';
import '../../../core/config/regions.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../application/commerce_providers.dart';
import '../domain/commerce_models.dart';

/// Plans & pricing (prototype `data-screen-label="Plans"`): the LIVE region
/// catalog (admin edits appear immediately), a One-time / Monthly / Yearly cycle
/// toggle, the three subscription tiers (Standard / Premium / Ultimate — Ultimate
/// only in paid-burial regions), the data-driven "MOST POPULAR" badge, promo
/// codes and self-serve billing.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});
  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  final _promo = TextEditingController();
  PromoValidation? _promoResult;
  bool _checking = false;
  String? _processingTier;

  /// Which billing cadence the grid shows: 'ONE_TIME' | 'MONTH' | 'YEAR'. Null
  /// until the catalog loads, then resolved to the cadence of the popular plan.
  String? _billingPeriod;

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  String get _region {
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn ? auth.user.region : 'US';
  }

  Future<void> _openUrl(String url) async {
    final ok = await safeLaunchExternal(url); // https-only: the checkout URL comes from the backend
    if (!ok && mounted) WasiatiSnack.danger(context, context.l10n.settingsLinkError);
  }

  Future<void> _startCheckout(PricingPlan plan) async {
    setState(() => _processingTier = plan.tier);
    try {
      // No region: the buyer is signed in, so the backend prices from their
      // ACCOUNT — a client-supplied region is exactly what let a VPN (or a hand-
      // edited request) change someone's currency.
      final url = await ref.read(paymentsApiProvider).checkout(
            tier: plan.tier,
            interval: plan.interval, // disambiguates monthly vs yearly vs one-time
            // Send whatever the buyer typed, not only a code they remembered to press
            // "Apply" on — a filled promo box that silently does nothing is the single
            // most common way a promo "doesn't work". The server re-validates against the
            // real tier (the preview above has no tier to send) and now returns a reason
            // instead of quietly charging full price, so an unusable code lands as a
            // readable error in the catch below.
            promoCode: _promo.text.trim().isEmpty ? null : _promo.text.trim(),
            successUrl: Env.checkoutSuccessUrl,
            cancelUrl: Env.checkoutCancelUrl,
          );
      await _openUrl(url);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _processingTier = null);
    }
  }

  /// We are the billing portal — our own engine runs the billing cycle and we
  /// don't use Stripe Billing, so there is no hosted portal to hand people to.
  void _manageBilling() => context.go('/billing');

  /// Offer banner CTA: drop the linked code into the promo field and validate it.
  void _applyOfferCode(String code) {
    _promo.text = code.toUpperCase();
    _checkPromo();
  }

  Future<void> _checkPromo() async {
    if (_promo.text.trim().isEmpty) return;
    setState(() => _checking = true);
    try {
      final res = await ref.read(commerceApiProvider).validatePromo(code: _promo.text.trim(), region: _region);
      if (!mounted) return; // navigated away mid-request — don't setState/read context after dispose
      setState(() => _promoResult = res);
    } catch (_) {
      if (!mounted) return;
      setState(() => _promoResult = PromoValidation(valid: false, reason: context.l10n.prCouldNotCheck));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final catalog = ref.watch(catalogProvider(_region));
    final regionName = switch (_region) {
      'KSA' => l.regionSaudiArabia,
      'CA' => l.regionCanada,
      _ => l.regionUnitedStates,
    };

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('${l.prLoadError} $e')),
          data: (cat) => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;
            // Cadences the region actually offers, and the one to show on load:
            // the cadence carrying the "most popular" plan, else the first present
            // in canonical order (One-time → Monthly → Yearly).
            const order = ['ONE_TIME', 'MONTH', 'YEAR'];
            final cadences = {for (final p in cat.plans) p.interval};
            final badged = cat.plans.where((p) => p.badge != null).map((p) => p.interval);
            final fallback = badged.where(cadences.contains).isNotEmpty
                ? badged.firstWhere(cadences.contains)
                : order.firstWhere(cadences.contains, orElse: () => 'ONE_TIME');
            final cycle = (_billingPeriod != null && cadences.contains(_billingPeriod)) ? _billingPeriod! : fallback;

            // Every BUYABLE tier for the selected cycle, ordered Standard →
            // Premium → Ultimate (sortOrder). `purchasable` is the backend's
            // product rule: Ultimate is absent from the one-time cycle because its
            // burial contributions are recurring, so there is no coherent one-time
            // version to sell. We hide rather than show-disabled so no price the
            // customer cannot act on is ever put in front of them; the note below
            // explains the absence.
            final cyclePlans = cat.plans.where((p) => p.interval == cycle && p.purchasable).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            // Ultimate exists in this region, but not on the cycle being shown.
            final ultimateHidden = cycle == 'ONE_TIME' &&
                cat.plans.any((p) => p.tier == 'ULTIMATE') &&
                !cyclePlans.any((p) => p.tier == 'ULTIMATE');

            return SingleChildScrollView(
              // The bar's height rides on the content, so the plan cards slide under the
              // glass mid-scroll and the promo card still comes to rest clear of it.
              padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                  EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Header: "Plans" + the region/currency line.
                    Text(l.prPlansTitle, style: t.headlineMedium),
                    const SizedBox(height: 4),
                    Text(l.prPlansSubtitle(regionName, cat.currency),
                        style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                    const SizedBox(height: 16),
                    // LIVE offer banner(s).
                    for (final offer in cat.offers) ...[
                      _OfferBanner(offer: offer, liveLabel: l.prLiveLabel, onApplyCode: _applyOfferCode),
                      const SizedBox(height: 12),
                    ],
                    // One-time / Monthly / Yearly toggle — only when the region
                    // offers more than one cadence.
                    if (cadences.length > 1) ...[
                      _BillingToggle(
                        period: cycle,
                        available: cadences,
                        onChanged: (v) => setState(() => _billingPeriod = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Cadence note: one-time terms, or the subscription commitment.
                    if (cycle == 'ONE_TIME')
                      Text(l.prOneTimeNote, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5))
                    else if (cycle == 'MONTH')
                      Text(l.prMonthlyCommit, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
                    if (cycle == 'ONE_TIME' || cycle == 'MONTH') const SizedBox(height: 16),
                    _PlansGrid(
                      plans: cyclePlans,
                      wide: wide,
                      processingTier: _processingTier,
                      onChoose: _startCheckout,
                    ),
                    // Free-burial regions (KSA, QA): explain why Ultimate is absent.
                    if (!regionRequiresPaidBurial(_region)) ...[
                      const SizedBox(height: 10),
                      Text(l.prNoUltimateNote(regionName),
                          style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
                    ]
                    // Paid-burial region on the one-time cycle: Ultimate is a
                    // subscription, so say why it isn't in the grid and what to do.
                    else if (ultimateHidden) ...[
                      const SizedBox(height: 10),
                      Text(l.prUltimateNotOneTime,
                          style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
                    ],
                    const SizedBox(height: 18),
                    _PromoBillingCard(
                      promo: _promo,
                      checking: _checking,
                      onApply: _checkPromo,
                      onManage: _manageBilling,
                      result: _promoResult,
                    ),
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

// --- LIVE offer banner ---------------------------------------------------
/// Prototype: a deep-green rail banner with a moon glyph, the live offer copy,
/// an optional apply CTA (only when the offer links a real promo code) and a
/// gold "LIVE" marker.
class _OfferBanner extends StatelessWidget {
  final Offer offer;
  final String liveLabel;
  final ValueChanged<String> onApplyCode;
  const _OfferBanner({required this.offer, required this.liveLabel, required this.onApplyCode});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: WasiatiColors.railGreen, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Text('🌙', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 11),
        Expanded(
          // badge and body are admin-authored in the commerce console for THIS banner;
          // the app used to drop both, so filling either field silently did nothing.
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(offer.title,
                    style: t.bodySmall?.copyWith(color: WasiatiColors.parchmentLight, fontWeight: FontWeight.w700)),
              ),
              if (offer.badge?.trim().isNotEmpty ?? false) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: WasiatiColors.brassGold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(offer.badge!.trim().toUpperCase(),
                      style: t.bodySmall?.copyWith(
                          color: WasiatiColors.railGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ],
            ]),
            if (offer.subtitle != null)
              Text(offer.subtitle!, style: t.bodySmall?.copyWith(color: WasiatiColors.goldSoft, fontSize: 11.5)),
            if (offer.body?.trim().isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(offer.body!,
                    style: t.bodySmall?.copyWith(
                        color: WasiatiColors.parchmentLight.withValues(alpha: 0.85),
                        fontSize: 11,
                        height: 1.4)),
              ),
          ]),
        ),
        // Only render the CTA when it has a real code to apply.
        if (offer.hasAction) ...[
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => onApplyCode(offer.promoCode!),
            style: WasiatiButtons.goldSolid(context).copyWith(
              minimumSize: WidgetStateProperty.all(const Size(0, 34)),
              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14)),
            ),
            child: Text(offer.ctaLabel!),
          ),
        ],
        const SizedBox(width: 12),
        Text(liveLabel,
            style: const TextStyle(
                color: WasiatiColors.goldSoft, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ]),
    );
  }
}

// --- One-time / Monthly / Yearly cadence toggle --------------------------
/// A sunken 3-segment control: the selected segment lifts to the card surface
/// with ink text; unselected segments are transparent + muted. The Yearly
/// segment carries a gold "SAVE 10%" pill.
class _BillingToggle extends StatelessWidget {
  final String period; // 'ONE_TIME' | 'MONTH' | 'YEAR'
  final Set<String> available;
  final ValueChanged<String> onChanged;
  const _BillingToggle({required this.period, required this.available, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ink = Theme.of(context).colorScheme.onSurface;
    const order = ['ONE_TIME', 'MONTH', 'YEAR'];
    final labels = {'ONE_TIME': l.prCycleOnce, 'MONTH': l.prBillingMonthly, 'YEAR': l.prCycleYearly};
    final present = order.where(available.contains).toList();

    Widget seg(String value) {
      final selected = period == value;
      final color = selected ? ink : context.tokens.muted;
      return InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? context.tokens.card : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(labels[value]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            if (value == 'YEAR') ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: WasiatiColors.goldDeep, borderRadius: BorderRadius.circular(99)),
                child: Text(l.prCycleYearlySave,
                    style: const TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w700, color: WasiatiColors.parchmentLight)),
              ),
            ],
          ]),
        ),
      );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: context.tokens.raised,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < present.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            seg(present[i]),
          ],
        ]),
      ),
    );
  }
}

// --- plans grid ----------------------------------------------------------
class _PlansGrid extends StatelessWidget {
  final List<PricingPlan> plans;
  final bool wide;
  final String? processingTier;
  final ValueChanged<PricingPlan> onChoose;
  const _PlansGrid({required this.plans, required this.wide, required this.processingTier, required this.onChoose});
  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return Text(context.l10n.prNoPlans,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.tokens.muted));
    }
    final cards = [
      for (final p in plans) _PlanCard(plan: p, busy: processingTier == p.tier, onChoose: () => onChoose(p)),
    ];
    if (!wide) {
      return Column(children: [
        for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: c),
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(child: cards[i]),
        ],
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PricingPlan plan;
  final bool busy;
  final VoidCallback onChoose;
  const _PlanCard({required this.plan, required this.busy, required this.onChoose});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final popular = plan.badge != null;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: context.tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: popular ? WasiatiColors.goldSoft : context.tokens.hairline,
            width: popular ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          // Plan name — display font (Fraunces), matching the prototype var(--fontD).
          Text(plan.displayName, style: t.headlineSmall?.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          // ONE-TIME shows a SINGLE price and nothing else — no "/mo", no "/yr".
          // You pay this once; a cadence suffix next to it would be a lie.
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: Text(plan.priceLabel, style: t.headlineMedium?.copyWith(fontSize: 27), overflow: TextOverflow.ellipsis),
            ),
            if (!plan.isOneTime) ...[
              const SizedBox(width: 5),
              Text(plan.interval == 'YEAR' ? l.prPerYear : l.prPerMonth,
                  style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ],
          ]),
          const SizedBox(height: 14),
          // Feature bullets — rendered from the live catalog (admin-editable).
          for (final f in plan.features)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.check, size: 16, color: context.tokens.successInk),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: t.bodySmall?.copyWith(fontSize: 12.5, height: 1.45, color: onSurface))),
              ]),
            ),
          const SizedBox(height: 14),
          popular
              ? FilledButton(
                  onPressed: busy ? null : onChoose,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: _label(l.prChoosePlan),
                )
              : OutlinedButton(
                  onPressed: busy ? null : onChoose,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: _label(l.prChoosePlan),
                ),
        ]),
      ),
      if (popular)
        // Badge pinned to the START edge (inset-inline-start:18, top:-11) — the
        // localized "MOST POPULAR" gold chip.
        PositionedDirectional(
          top: -11,
          start: 18,
          child: WasiatiChip(l.prMostPopular, kind: WasiatiChipKind.mostPopular),
        ),
    ]);
  }

  Widget _label(String s) => busy
      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(s);
}

// --- promo code + manage billing -----------------------------------------
/// Prototype's promo/billing card: apply a promo code (also honoured at Stripe
/// checkout) and open the self-serve billing portal.
class _PromoBillingCard extends StatelessWidget {
  final TextEditingController promo;
  final bool checking;
  final VoidCallback onApply;
  final VoidCallback onManage;
  final PromoValidation? result;
  const _PromoBillingCard({
    required this.promo,
    required this.checking,
    required this.onApply,
    required this.onManage,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return WasiatiCard(
      padding: const EdgeInsets.all(18),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.prPromoTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l.prPromoCheckoutNote, style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 11)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: promo,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: l.prPromoHint, isDense: true),
              onSubmitted: (_) => onApply(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: checking ? null : onApply,
            child: checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.prApply),
          ),
        ]),
        if (result != null) ...[
          const SizedBox(height: 8),
          // Status marker is a bundled Material icon, not a Unicode ✓/✕ (absent
          // from the app fonts and would render as tofu).
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(result!.valid ? Icons.check_rounded : Icons.close_rounded,
                size: 15, color: result!.valid ? context.tokens.successInk : context.tokens.dangerInk),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                result!.valid ? (result!.description ?? l.prCodeApplied) : (result!.reason ?? l.prInvalidCode),
                style: t.bodySmall?.copyWith(color: result!.valid ? context.tokens.successInk : context.tokens.dangerInk),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onManage,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              child: Text(l.prManageBilling),
            ),
          ),
        ]),
      ]),
    );
  }
}
