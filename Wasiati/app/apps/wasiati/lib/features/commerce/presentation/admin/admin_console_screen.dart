import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../../core/l10n/l10n.dart';
import '../../application/commerce_providers.dart';
import '../../domain/commerce_models.dart';

/// Locale-aware short date (Arabic numerals follow the AR locale automatically).
String _fmtDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(context.l10n.localeName).format(d.toLocal());

/// Admin console for the no-code commerce catalog (design 8a): edit prices,
/// manage promos and offers at runtime. ADMIN-only (guarded in the router).
class AdminConsoleScreen extends StatelessWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        // bottom: false — the shell's frosted bar overlaps the body, and its height is
        // spent on each tab's own scroll padding instead (see AppShell's extendBody).
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Row(children: [
                const Seal(size: 32, status: SealStatus.verified),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.adminCommerceEyebrow,
                        style: TextStyle(color: context.tokens.goldInk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    Text(l.adminCommerceTitle, style: Theme.of(context).textTheme.titleLarge),
                  ]),
                ),
              ]),
            ),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              // The selected tab LABEL is type, so it takes the ink, not the fill:
              // bottleGreen on the night scaffold was 1.34:1.
              labelColor: context.tokens.greenInk,
              indicatorColor: WasiatiColors.brassGold,
              tabs: [Tab(text: l.adminCommerceTabPlans), Tab(text: l.adminCommerceTabPromotions), Tab(text: l.adminCommerceTabOffers)],
            ),
            const Expanded(child: TabBarView(children: [_PlansTab(), _PromotionsTab(), _OffersTab()])),
          ]),
        ),
      ),
    );
  }
}

// --- Plans ---
class _PlansTab extends ConsumerWidget {
  const _PlansTab();

  Future<void> _editPrice(BuildContext context, WidgetRef ref, PricingPlan plan) async {
    final l = context.l10n;
    final controller = TextEditingController(text: (plan.unitAmount / 100).toStringAsFixed(2));
    try {
      final newMajor = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${plan.displayName} · ${plan.region}'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l.adminPlanPriceLabel(plan.currency), prefixText: '${plan.currency} '),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(l.commonSave)),
          ],
        ),
      );
      if (newMajor == null) return;
      final minor = (double.tryParse(newMajor) ?? plan.unitAmount / 100) * 100;
      await ref.read(commerceApiProvider).adminUpdatePlan(plan.id, {'unitAmount': minor.round()});
      ref.invalidate(adminPlansProvider);
      ref.invalidate(catalogProvider);
      if (context.mounted) WasiatiSnack.success(context, l.adminPlanPriceUpdated);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final plans = ref.watch(adminPlansProvider);
    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => ListView(
        // The bar's height rides on the content, so plan rows slide under the glass
        // mid-scroll and the last one still comes to rest clear of it.
        padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        children: [
          for (final p in list)
            _AdminCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(p.displayName, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      WasiatiChip(p.region, kind: WasiatiChipKind.region),
                    ]),
                    const SizedBox(height: 4),
                    // Raw interval/tier enums, like `p.tier` and `p.region` above:
                    // this is the admin catalog, where the identifier IS the useful
                    // label and a translated one would obscure which row is which.
                    Text('${p.priceLabel} ${p.interval}  ·  ${p.tier}',
                        style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                  ]),
                ),
                TextButton(onPressed: () => _editPrice(context, ref, p), child: Text(l.adminPlanEditPrice)),
              ]),
            ),
        ],
      ),
    );
  }
}

// --- Promotions ---
class _PromotionsTab extends ConsumerWidget {
  const _PromotionsTab();

  /// Runs [action] and refreshes the list; failures surface as a snack rather
  /// than a silent unhandled future.
  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action, String successMsg) async {
    try {
      await action();
      ref.invalidate(adminPromotionsProvider);
      if (context.mounted) WasiatiSnack.success(context, successMsg);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  /// One dialog for both halves of the lifecycle: no [existing] = create,
  /// [existing] = edit, pre-filled — including the limits, so a seeded code like
  /// LAUNCH25 (no cap, no expiry) can be given both without touching the DB.
  ///
  /// The dialog is a real StatefulWidget owning its controllers — disposing them
  /// here in a finally (the old shape) raced the closing transition, which
  /// rebuilds the fields one last frame after the pop and threw
  /// "TextEditingController was used after being disposed".
  Future<void> _promoDialog(BuildContext context, WidgetRef ref, {Promotion? existing}) async {
    final l = context.l10n;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PromoDialog(existing: existing),
    );
    if (payload == null || !context.mounted) return;
    final api = ref.read(commerceApiProvider);
    if (existing != null) {
      await _act(context, ref, () => api.adminUpdatePromotion(existing.id, payload), l.adminPromoUpdated);
    } else {
      await _act(context, ref, () => api.adminCreatePromotion(payload), l.adminPromoCreated);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final promos = ref.watch(adminPromotionsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // The FAB floats against THIS Scaffold, which now runs full-bleed behind the shell's
      // glass bar — and Scaffold only lifts a FAB clear of viewPadding, which the bar is
      // not. Without this the button parks underneath the glass, out of reach.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: FloatingActionButton.extended(
          onPressed: () => _promoDialog(context, ref),
          backgroundColor: WasiatiColors.bottleGreen,
          icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 24, color: WasiatiColors.onDark),
          label: Text(l.adminPromoNewButton, style: const TextStyle(color: WasiatiColors.onDark)),
        ),
      ),
      body: promos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.adminPromoEmpty, style: t.bodyLarge?.copyWith(color: context.tokens.muted)))
            : ListView(
                // The bar's height rides on the content, so promo rows slide under the glass
                // mid-scroll. The SizedBox below already clears the FAB; this clears the bar.
                padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                children: [
                  for (final p in list)
                    _AdminCard(
                      child: Row(children: [
                        Icon(Icons.local_offer_outlined,
                            color: p.isLiveAt(DateTime.now()) ? context.tokens.greenInk : context.tokens.muted),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(p.code, style: t.titleMedium, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              _PromoStatusChip(promo: p),
                            ]),
                            Text(
                              '${p.valueLabel}${p.description != null ? ' · ${p.description}' : ''}  ·  '
                              // A capped code shows "3 of 100 used" so the cap is
                              // legible at a glance; an uncapped one keeps the
                              // plain counter. digits() localizes the count under AR.
                              '${context.digits(p.maxRedemptions != null ? l.adminPromoUsedOf(p.timesRedeemed, p.maxRedemptions!) : l.adminPromoUsed(p.timesRedeemed))}',
                              style: t.bodySmall?.copyWith(color: context.tokens.muted),
                            ),
                            if (p.startsAt != null || p.endsAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (p.startsAt != null) l.adminPromoWindowFrom(_fmtDate(context, p.startsAt!)),
                                  if (p.endsAt != null) l.adminPromoWindowUntil(_fmtDate(context, p.endsAt!)),
                                ].join(' · '),
                                style: t.bodySmall?.copyWith(color: context.tokens.faint),
                              ),
                            ],
                          ]),
                        ),
                        IconButton(
                          tooltip: l.adminPromoEditTooltip,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _promoDialog(context, ref, existing: p),
                        ),
                        // Archive/Reinstate, not Delete: DELETE archives server-side
                        // (reversible, redemption count kept), so the trash-can icon
                        // this used to be was promising a permanence that no longer
                        // exists — and hiding that the code could come back.
                        if (p.active)
                          IconButton(
                            tooltip: l.adminPromoArchive,
                            icon: const Icon(Icons.archive_outlined),
                            onPressed: () => _act(context, ref,
                                () => ref.read(commerceApiProvider).adminDeletePromotion(p.id), l.adminPromoArchived),
                          )
                        else
                          IconButton(
                            tooltip: l.adminPromoReinstate,
                            icon: const Icon(Icons.unarchive_outlined),
                            onPressed: () => _act(context, ref,
                                () => ref.read(commerceApiProvider).adminReinstatePromotion(p.id), l.adminPromoReinstated),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 72),
                ],
              ),
      ),
    );
  }
}

/// The create/edit form. A StatefulWidget rather than a StatefulBuilder closure
/// so the TextEditingControllers are disposed by the route's own lifecycle —
/// after the exit animation — never by the opener while the fields still render.
/// Pops the request payload; the opener owns the API call.
class _PromoDialog extends StatefulWidget {
  final Promotion? existing;
  const _PromoDialog({this.existing});
  @override
  State<_PromoDialog> createState() => _PromoDialogState();
}

class _PromoDialogState extends State<_PromoDialog> {
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _maxRedemptions;
  late String _type;
  late bool _firstTimeOnly;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _error;

  Promotion? get existing => widget.existing;
  bool get isEdit => existing != null;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: existing?.code ?? '');
    _value = TextEditingController(text: '${existing?.value ?? 25}');
    _maxRedemptions = TextEditingController(text: existing?.maxRedemptions?.toString() ?? '');
    _type = existing?.type ?? 'PERCENT';
    _firstTimeOnly = existing?.firstTimeOnly ?? false;
    // The dialog thinks in LOCAL days (see _pickDate); stored instants come back UTC.
    _startsAt = existing?.startsAt?.toLocal();
    _endsAt = existing?.endsAt?.toLocal();
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxRedemptions.dispose();
    super.dispose();
  }

  // Dates only — the backend stores an instant, but an admin thinks in days.
  // Start = 00:00 local, end = 23:59:59 so "ends 1 Aug" includes all of 1 Aug
  // rather than expiring at midnight as it begins.
  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startsAt : _endsAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
      _error = null;
    });
  }

  Widget _dateRow(String label, DateTime? v, {required bool isStart}) {
    final l = context.l10n;
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () => _pickDate(isStart: isStart),
          style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
          child: Text('$label: ${v == null ? l.adminPromoDateAny : _fmtDate(context, v)}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      if (v != null)
        IconButton(
          tooltip: l.adminPromoDateClear,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() {
            if (isStart) {
              _startsAt = null;
            } else {
              _endsAt = null;
            }
            _error = null;
          }),
        ),
    ]);
  }

  /// What the opener sends to the API. Edit sends EVERY limit — this dialog
  /// displays every limit, so an emptied field is a decision, and an explicit
  /// null is the backend's contract for CLEAR. Create omits empties: there is
  /// nothing to clear yet.
  Map<String, dynamic> _payload() {
    final cap = int.tryParse(_maxRedemptions.text.trim());
    if (isEdit) {
      return {
        'code': _code.text.trim().toUpperCase(),
        'type': _type,
        'value': int.tryParse(_value.text) ?? existing!.value,
        if (_type == 'AMOUNT') 'currency': existing!.currency ?? 'USD',
        'maxRedemptions': (cap != null && cap > 0) ? cap : null,
        'startsAt': _startsAt?.toUtc().toIso8601String(),
        'endsAt': _endsAt?.toUtc().toIso8601String(),
        'firstTimeOnly': _firstTimeOnly,
      };
    }
    return {
      'code': _code.text.trim().toUpperCase(),
      'type': _type,
      'value': int.tryParse(_value.text) ?? 25,
      if (_type == 'AMOUNT') 'currency': 'USD',
      if (cap != null && cap > 0) 'maxRedemptions': cap,
      if (_startsAt != null) 'startsAt': _startsAt!.toUtc().toIso8601String(),
      if (_endsAt != null) 'endsAt': _endsAt!.toUtc().toIso8601String(),
      if (_firstTimeOnly) 'firstTimeOnly': true,
    };
  }

  void _save() {
    final l = context.l10n;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = l.adminPromoErrorCodeRequired);
      return;
    }
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      setState(() => _error = l.adminPromoErrorEndBeforeStart);
      return;
    }
    Navigator.pop(context, _payload());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(isEdit ? l.adminPromoEditTitle : l.adminPromoNewTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: l.adminPromoCodeLabel)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: InputDecoration(labelText: l.adminPromoTypeLabel),
              items: [
                DropdownMenuItem(value: 'PERCENT', child: Text(l.adminPromoTypePercent)),
                DropdownMenuItem(value: 'AMOUNT', child: Text(l.adminPromoTypeAmount)),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'PERCENT'),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: _type == 'PERCENT' ? l.adminPromoValuePercentLabel : l.adminPromoValueAmountLabel)),

            // --- Limits: how many, and when. All optional; empty = unlimited/open.
            const SizedBox(height: 20),
            Text(l.adminPromoLimitsSection, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            TextField(
              controller: _maxRedemptions,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.adminPromoMaxRedemptionsLabel,
                helperText: l.adminPromoMaxRedemptionsHelper,
              ),
            ),
            const SizedBox(height: 12),
            _dateRow(l.adminPromoStartsAtLabel, _startsAt, isStart: true),
            const SizedBox(height: 8),
            _dateRow(l.adminPromoEndsAtLabel, _endsAt, isStart: false),
            const SizedBox(height: 4),
            // Server-enforced: validate() refuses the code for anyone with a
            // prior Invoice (this switch used to be deliberately withheld while
            // the column was decorative — the enforcement is wired now).
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.adminPromoFirstTimeOnlyLabel),
              subtitle: Text(l.adminPromoFirstTimeOnlyHelper,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.tokens.muted)),
              value: _firstTimeOnly,
              onChanged: (v) => setState(() => _firstTimeOnly = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WasiatiColors.danger)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _save, child: Text(isEdit ? l.commonSave : l.adminPromoCreate)),
      ],
    );
  }
}

/// Why a code is (or isn't) working right now. The server is the authority —
/// this mirrors its checks so an admin isn't left guessing why a live code was
/// refused at checkout.
class _PromoStatusChip extends StatelessWidget {
  final Promotion promo;
  const _PromoStatusChip({required this.promo});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = DateTime.now();
    // Order matters: report the FIRST reason the server would reject on, so the
    // chip names the actual blocker rather than a later incidental one.
    final (String label, Color color) = switch (promo) {
      _ when !promo.active => (l.adminPromoStatusInactive, context.tokens.muted),
      _ when promo.isExhausted => (l.adminPromoStatusExhausted, WasiatiColors.danger),
      _ when promo.isExpiredAt(now) => (l.adminPromoStatusExpired, WasiatiColors.danger),
      _ when promo.isScheduledAt(now) => (l.adminPromoStatusScheduled, WasiatiColors.goldDeep),
      _ => (l.adminPromoStatusLive, context.tokens.greenInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // 0.08 for the same reason as the burial estimate chip: labelSmall type on a
        // wash of its own colour is 4.35:1 at 12%, under the 4.5 bar. Applies to every
        // status here, gold and danger alike.
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}

// --- Offers ---
class _OffersTab extends ConsumerWidget {
  const _OffersTab();

  /// Runs [action] and refreshes both the admin list and the public storefront
  /// (offer cards render there); failures surface as a snack rather than a
  /// silent unhandled future.
  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action, String successMsg) async {
    try {
      await action();
      ref.invalidate(adminOffersProvider);
      ref.invalidate(catalogProvider);
      if (context.mounted) WasiatiSnack.success(context, successMsg);
    } catch (e) {
      if (context.mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  /// Edits the storefront card's copy (PATCH /admin/commerce/offers/:id) —
  /// until this was wired an offer, once created, could never be reworded.
  /// The active toggle lives on the row; this dialog owns the wording. Every
  /// optional field is IN the dialog, so an emptied one is a decision: explicit
  /// null clears the column server-side (UpdateOfferDto spreads into Prisma).
  Future<void> _editOffer(BuildContext context, WidgetRef ref, Offer offer) async {
    final l = context.l10n;
    final title = TextEditingController(text: offer.title);
    final subtitle = TextEditingController(text: offer.subtitle ?? '');
    final badge = TextEditingController(text: offer.badge ?? '');
    final cta = TextEditingController(text: offer.ctaLabel ?? '');
    String? error;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l.adminOfferEditTitle),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(controller: title, decoration: InputDecoration(labelText: l.adminOfferTitleLabel)),
                  const SizedBox(height: 12),
                  TextField(controller: subtitle, decoration: InputDecoration(labelText: l.adminOfferSubtitleLabel)),
                  const SizedBox(height: 12),
                  TextField(controller: badge, decoration: InputDecoration(labelText: l.adminOfferBadgeLabel)),
                  const SizedBox(height: 12),
                  TextField(controller: cta, decoration: InputDecoration(labelText: l.adminOfferCtaLabel)),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: WasiatiColors.danger)),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().isEmpty) {
                    setLocal(() => error = l.adminOfferErrorTitleRequired);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(l.commonSave),
              ),
            ],
          ),
        ),
      );
      if (saved != true || !context.mounted) return;
      String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      await _act(context, ref, () => ref.read(commerceApiProvider).adminUpdateOffer(offer.id, {
            'title': title.text.trim(),
            'subtitle': opt(subtitle),
            'badge': opt(badge),
            'ctaLabel': opt(cta),
          }), l.adminOfferSaved);
    } finally {
      title.dispose();
      subtitle.dispose();
      badge.dispose();
      cta.dispose();
    }
  }

  /// DELETE is a hard delete here (no archive/reinstate, unlike promotions), so
  /// it asks first and says so.
  Future<void> _deleteOffer(BuildContext context, WidgetRef ref, Offer offer) async {
    final l = context.l10n;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminOfferDeleteTitle),
        content: Text(l.adminOfferDeleteBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WasiatiColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    await _act(context, ref, () => ref.read(commerceApiProvider).adminDeleteOffer(offer.id), l.adminOfferDeleted);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final offers = ref.watch(adminOffersProvider);
    return offers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? Center(child: Text(l.adminOfferEmpty, style: t.bodyLarge?.copyWith(color: context.tokens.muted)))
          : ListView(
              // The bar's height rides on the content, so offer rows slide under the glass
              // mid-scroll and the last one still comes to rest clear of it.
              padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              children: [
                for (final o in list)
                  _AdminCard(
                    child: Row(children: [
                      Seal(size: 34, status: o.active ? SealStatus.sealed : SealStatus.idle),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o.title, style: t.titleMedium),
                          Text(o.subtitle ?? o.ctaLabel ?? '', style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                        ]),
                      ),
                      // Live/off is a one-tap toggle (PATCH {active}) — pulling a
                      // stale banner should not require an edit dialog.
                      Tooltip(
                        message: o.active ? l.adminOfferLive : l.adminOfferOff,
                        child: Switch(
                          value: o.active,
                          onChanged: (v) => _act(
                              context,
                              ref,
                              () => ref.read(commerceApiProvider).adminUpdateOffer(o.id, {'active': v}),
                              v ? l.adminOfferActivated : l.adminOfferDeactivated),
                        ),
                      ),
                      IconButton(
                        tooltip: l.adminOfferEditTooltip,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editOffer(context, ref, o),
                      ),
                      IconButton(
                        tooltip: l.commonDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteOffer(context, ref, o),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final Widget child;
  const _AdminCard({required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: child,
    );
  }
}

