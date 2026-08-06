import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../commerce/application/entitlement_providers.dart';
import '../../identity/application/identity_providers.dart';
import '../../../core/providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/domain/auth_models.dart';
import '../../wills/application/wills_providers.dart';
import '../../wills/domain/wills_models.dart';
import '../../vault/application/vault_providers.dart';
import '../../referrals/application/referrals_providers.dart';

/// The signed-in home (DV2.1 "Dashboard"): a warm greeting with region/plan/identity
/// chips, the "Your legacy, in order" checklist, a horizontal wills summary, the four
/// estate stat cards (vault · heirs · witnesses · trustee), the cream plan card, and
/// the dark referral rail.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthSignedIn ? auth.user : null;
    final wills = ref.watch(willsListProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          // Desktop uses a main + sidebar layout (primary cards left, account cards
          // right) up to 1120px; phone/tablet keep the single 720px column. This stops
          // the dashboard from being a narrow strip on wide monitors.
          final wide = box.maxWidth >= 960;
          final primary = <Widget>[
            _ChecklistCard(wills: wills),
            const SizedBox(height: 20),
            _WillsSummaryCard(wills: wills),
            const SizedBox(height: 20),
            _StatsGrid(wills: wills),
          ];
          final aside = <Widget>[
            _PlanCard(entitlement: ref.watch(entitlementProvider)),
            const SizedBox(height: 20),
            const _ReferralRail(),
          ];
          return SingleChildScrollView(
            // The bar's height rides on the content, so cards slide under the glass
            // mid-scroll and the last one still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1120 : 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(user: user, wide: wide),
                    const SizedBox(height: 20),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 62,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: primary),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 38,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: aside),
                          ),
                        ],
                      )
                    else ...[
                      ...primary,
                      const SizedBox(height: 20),
                      ...aside,
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// --- header --------------------------------------------------------------
class _Header extends ConsumerWidget {
  final AuthUser? user;
  final bool wide;
  const _Header({required this.user, required this.wide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final greeting = l.dashGreeting(_displayName(user?.email));
    final region = _region(user?.region);
    // Reflect the real tier. `tier: null` is the server saying FREE — `?? 'STANDARD'`
    // used to relabel exactly the account the paywall applies to as a paying one. While
    // loading there is no claim to make, so no chip: a wrong flash is worse than a gap.
    final tier = ref.watch(entitlementProvider).maybeWhen(
        data: (d) => d['tier'] == null ? l.auPlanFree : _titleCase(d['tier'].toString()),
        orElse: () => null);
    final idStatus =
        ref.watch(identityStatusProvider).maybeWhen(data: (s) => s.status, orElse: () => 'UNVERIFIED');

    final chips = Wrap(spacing: 8, runSpacing: 8, children: [
      WasiatiChip('${region.code} · ${region.currency}', kind: WasiatiChipKind.region),
      if (tier != null) WasiatiChip(tier, kind: WasiatiChipKind.region),
      _IdentityChip(status: idStatus),
    ]);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting, style: text.headlineMedium),
        const SizedBox(height: 10),
        chips,
      ],
    );
    final createBtn = FilledButton.icon(
      onPressed: () => context.go('/wills/new'),
      icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
      label: Text(l.dashCreateWill),
    );
    if (!wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title,
        const SizedBox(height: 14),
        Align(alignment: AlignmentDirectional.centerStart, child: createBtn),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: title),
      const SizedBox(width: 16),
      createBtn,
    ]);
  }
}

/// Outlined, clickable identity-status chip. Colour + copy track KYC status;
/// tapping opens the KYC screen.
class _IdentityChip extends StatelessWidget {
  final String status;
  const _IdentityChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (label, color, svg) = switch (status) {
      'VERIFIED' => (l.dashVerified, context.tokens.successInk, WasiatiIcons.check),
      'PENDING' => (l.dashIdPending, context.tokens.warningInk, null),
      _ => (l.dashIdUnverified, context.tokens.muted, null),
    };
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
        side: BorderSide(color: context.tokens.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/kyc'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (svg != null) ...[WasiatiIcon(svg: svg, size: 13, color: color), const SizedBox(width: 5)],
            Text(label,
                style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
          ]),
        ),
      ),
    );
  }
}

// --- checklist / progress ------------------------------------------------
class _ChecklistCard extends ConsumerWidget {
  final AsyncValue<List<Will>> wills;
  const _ChecklistCard({required this.wills});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final list = wills.asData?.value ?? const <Will>[];
    final primary = list.isNotEmpty ? list.first : null;
    final verified =
        ref.watch(identityStatusProvider).maybeWhen(data: (s) => s.status == 'VERIFIED', orElse: () => false);
    final heirsAdded = primary?.shariaShares.isNotEmpty ?? false;
    final sealed = list.any((w) => w.locked);
    final willTarget = primary != null ? '/wills/${primary.id}' : '/wills';

    // Each row lands on the thing it names. "Add your heirs" goes to the heirs
    // section, and "Seal your will" to the Review page where sealing actually
    // happens — both used to drop the owner at the top of the will and leave them
    // to work out which of its cards they had been sent for.
    final items = <({String label, bool done, VoidCallback go})>[
      (label: l.dashCkIdentity, done: verified, go: () => context.go('/kyc')),
      (
        label: l.dashCkHeirs,
        done: heirsAdded,
        go: () => context.go(primary != null ? '$willTarget?focus=heirs' : '/wills')
      ),
      (
        label: l.dashCkSealed,
        done: sealed,
        // Sealing lives on Review, not on the detail page. Once it IS sealed there is
        // nothing left to do there, so the will itself is the honest destination.
        go: () => context.go(primary == null ? '/wills' : (sealed ? willTarget : '$willTarget/review'))
      ),
      (label: l.dashCkVideo, done: false, go: () => context.go('/legacy/record')),
    ];
    final done = items.where((i) => i.done).length;
    final progress = items.isEmpty ? 0.0 : done / items.length;

    return WasiatiCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(l.dashChecklistTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(context.digits(l.dashChecklistCount(done, items.length)),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.tokens.goldInk)),
        ]),
        const SizedBox(height: 12),
        // 7px gold progress bar over a sunken track.
        SizedBox(
          height: 7,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: context.tokens.raised)),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                alignment: AlignmentDirectional.centerStart,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: context.tokens.gold, borderRadius: BorderRadius.circular(99)),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          return _flowGrid(
            c,
            [for (final i in items) _ChecklistItem(label: i.label, done: i.done, onTap: i.go)],
            minItem: 180,
            gap: 8,
          );
        }),
      ]),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;
  const _ChecklistItem({required this.label, required this.done, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      // greenTint is a LIGHT-theme fill. Hard-coded here it painted the three
      // outstanding checklist rows a pale cold panel on a night card — the
      // reported "baby blue highlighted boxes in dark mode". tokens.highlight is
      // that same greenTint on light (so light mode is unchanged) and greenDeep
      // on dark.
      color: done ? Colors.transparent : context.tokens.highlight,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? WasiatiColors.success : Colors.transparent,
                border: Border.all(color: done ? WasiatiColors.success : context.tokens.hairline, width: 1.5),
              ),
              child: done
                  ? const WasiatiIcon(svg: WasiatiIcons.check, size: 11, color: WasiatiColors.parchmentLight)
                  : null,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: done ? context.tokens.muted : context.tokens.greenInk,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

// --- wills summary (horizontal) ------------------------------------------
class _WillsSummaryCard extends StatelessWidget {
  final AsyncValue<List<Will>> wills;
  const _WillsSummaryCard({required this.wills});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return WasiatiCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      onTap: () => context.go('/wills'),
      child: wills.when(
        loading: () => const _WillsSummarySkeleton(),
        error: (e, _) => _CardMessage(icon: Icons.error_outline, text: l.dashWillsLoadError),
        data: (list) {
          final sealedCount = list.where((w) => w.locked).length;
          Will? draft;
          for (final w in list) {
            if (w.isFlowDraft) {
              draft = w;
              break;
            }
          }
          return Row(children: [
            const _DiamondCheck(size: 52, fill: WasiatiColors.brassGold, glyph: WasiatiColors.parchmentLight),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.dashWillsSummaryTitle,
                    style: text.headlineSmall?.copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: context.tokens.successInk),
                    ),
                    const SizedBox(width: 6),
                    Text(context.digits(l.dashSealedCountLine(sealedCount)),
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600, color: context.tokens.successInk)),
                  ]),
                  if (draft != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _DraftBadge(label: l.dashDraftLbl),
                      const SizedBox(width: 7),
                      Text(context.digits(l.dashDraftStep(draft.draftStep)),
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600, color: context.tokens.goldInk)),
                    ])
                  else
                    Text(l.dashNoDraftLine,
                        style: text.bodySmall?.copyWith(fontSize: 12.5, color: context.tokens.faint)),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            if (draft != null) ...[
              FilledButton(
                // Into the guided steps, not the will detail. The detail page's only
                // forward action is Review & seal, which made steps 1-5 unreachable from
                // any draft the owner came back to.
                onPressed: () => context.go('/wills/${draft!.id}/edit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Text(l.dashContinueDraft),
              ),
              const SizedBox(width: 12),
            ],
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(l.dashOpen,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.tokens.goldInk)),
              const SizedBox(width: 2),
              WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 15, color: context.tokens.goldInk),
            ]),
          ]);
        },
      ),
    );
  }
}

class _DraftBadge extends StatelessWidget {
  final String label;
  const _DraftBadge({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: context.tokens.gold, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.goldInk)),
      );
}

class _WillsSummarySkeleton extends StatelessWidget {
  const _WillsSummarySkeleton();
  @override
  Widget build(BuildContext context) => const Row(children: [
        WasiatiSkeleton(width: 52, height: 52, radius: 12),
        SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            WasiatiSkeleton(width: 120, height: 16),
            SizedBox(height: 8),
            WasiatiSkeleton(width: 200, height: 12),
          ]),
        ),
      ]);
}

// --- stat cards ----------------------------------------------------------
class _StatsGrid extends ConsumerWidget {
  final AsyncValue<List<Will>> wills;
  const _StatsGrid({required this.wills});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final data = wills.asData?.value;
    final will = (data != null && data.isNotEmpty) ? data.first : null;

    // Vault (global, not per-will).
    final vault = ref.watch(vaultListProvider);
    final vaultCount = vault.asData?.value.length;

    // Per-will registries.
    final heirContacts =
        will == null ? const AsyncValue<List<HeirContact>>.data([]) : ref.watch(heirContactsProvider(will.id));
    final witnesses = will == null ? const AsyncValue<List<Witness>>.data([]) : ref.watch(witnessesProvider(will.id));
    final trustees = will == null ? const AsyncValue<List<Trustee>>.data([]) : ref.watch(trusteesProvider(will.id));

    final heirs = heirContacts.asData?.value;
    final missing = heirs?.where((h) => !h.isComplete).length;
    final heirIncomplete = (missing ?? 0) > 0;

    final wList = witnesses.asData?.value;
    final wConfirmed = wList?.where((w) => _confirmed(w.status)).length;
    final wTotal = wList?.length;
    final wNames = (wList ?? const <Witness>[])
        .map((w) => w.fullName.trim().split(RegExp(r'\s+')).first)
        .where((n) => n.isNotEmpty)
        .toList();

    final tCount = trustees.asData?.value.length;
    final willTarget = will != null ? '/wills/${will.id}' : '/wills';
    // Each tile stands for one section of the will, so each one lands ON that section
    // (`?focus=`) rather than at the top of a long two-column page. Half of these had no
    // tap target at all, and the ones that did dropped the owner at the top and left
    // them to find what they had clicked.
    String section(String s) => will != null ? '$willTarget?focus=$s' : '/wills';

    final cards = <Widget>[
      _StatTile(
        title: l.dashVault,
        // bottleGreen is 1.59:1 on a night card — the vault glyph was effectively
        // invisible in dark. The other three tiles already take theme-resolved inks.
        icon: WasiatiIcon(svg: WasiatiIcons.vault, size: 22, color: context.tokens.greenInk),
        value: vaultCount?.toString() ?? '—',
        suffix: l.dashSecretsStored,
        caption: l.dashEncryptedLocked,
        onTap: () => context.go('/vault'),
      ),
      _StatTile(
        title: l.dashHeirContacts,
        icon: WasiatiIcon(
            svg: WasiatiIcons.heirContacts,
            size: 22,
            color: heirIncomplete ? context.tokens.warningInk : context.tokens.successInk),
        value: (missing ?? 0).toString(),
        valueColor: heirIncomplete ? context.tokens.warningInk : context.tokens.successInk,
        suffix: heirIncomplete ? l.dashContactsMissing : l.dashContactsComplete,
        caption: l.dashContactsMeta,
        borderColor: heirIncomplete ? WasiatiColors.warning : null,
        onTap: () => context.go(section('heirs')),
      ),
      _StatTile(
        title: l.dashWitnesses,
        icon: WasiatiIcon(svg: WasiatiIcons.witnesses, size: 22, color: context.tokens.infoInk),
        value: wTotal == null ? '—' : '${wConfirmed ?? 0} / $wTotal',
        suffix: l.dashConfirmed,
        caption: wNames.isNotEmpty ? wNames.join(' · ') : l.dashWitnessesCaption,
        onTap: () => context.go(section('witnesses')),
      ),
      _StatTile(
        title: l.dashTrustee,
        icon: WasiatiIcon(svg: WasiatiIcons.trustee, size: 22, color: context.tokens.muted),
        value: tCount?.toString() ?? '—',
        suffix: l.dashPendingCode,
        onTap: () => context.go(section('trustees')),
        action: _ResendLink(label: l.dashResendSms, onTap: () => context.go(section('trustees'))),
      ),
    ];

    return LayoutBuilder(builder: (context, c) => _flowGrid(c, cards, minItem: 160, gap: 16));
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final Widget icon;
  final String value;
  final String? suffix;
  final Color? valueColor;
  final String? caption;
  final Widget? action;
  final VoidCallback? onTap;
  final Color? borderColor;
  const _StatTile({
    required this.title,
    required this.icon,
    required this.value,
    this.suffix,
    this.valueColor,
    this.caption,
    this.action,
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final display = Theme.of(context).textTheme.headlineSmall;
    return WasiatiCard(
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      borderColor: borderColor,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          icon,
        ]),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(
            text: value,
            style: display?.copyWith(fontSize: 24, fontWeight: FontWeight.w600, color: valueColor),
          ),
          if (suffix != null)
            TextSpan(
              text: ' $suffix',
              style: display?.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: context.tokens.muted),
            ),
        ])),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!, style: TextStyle(fontSize: 11.5, color: context.tokens.muted)),
        ],
        if (action != null) ...[
          const SizedBox(height: 4),
          action!,
        ],
      ]),
    );
  }
}

class _ResendLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ResendLink({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.tokens.goldInk)),
      );
}

// --- plan / entitlement card (cream) -------------------------------------
class _PlanCard extends StatelessWidget {
  final AsyncValue<Map<String, dynamic>> entitlement;
  const _PlanCard({required this.entitlement});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: context.tokens.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.tokens.hairline),
        ),
        child: Stack(children: [
          // Faint diamond watermark, bottom-trailing corner.
          PositionedDirectional(
            end: -28,
            bottom: -28,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.08,
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      // At 8% opacity a bottle-green outline is invisible on a
                      // night card; the watermark has to invert with the surface.
                      border: Border.all(color: context.tokens.greenInk, width: 4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: entitlement.when(
              loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(color: WasiatiColors.goldSoft))),
              error: (e, _) => Text(l.dashPlanLoadError, style: text.bodyMedium),
              data: (data) {
                // `tier: null` is the server saying FREE. `?? 'STANDARD'` used to relabel
                // exactly the account the paywall applies to as a paying one — and the
                // first two perks were hard-coded ticks, so a free (or one-time Basic)
                // account was shown the vault and unlimited edits as INCLUDED while every
                // tap on them 403'd. The server sends `features` precisely so the UI can
                // tell the truth per-perk; entitlementHas is this file's own sibling
                // helper for reading it, and this card was the path that dropped it.
                final tierRaw = data['tier']?.toString();
                final isFree = tierRaw == null;
                final isPremiumPlus = !isFree && _isPremiumPlus(tierRaw);
                final hasEdits = entitlementHas(data, 'unlimitedEdits');
                final hasVault = entitlementHas(data, 'vault');
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.dashYourPlan.toUpperCase(),
                      style: TextStyle(
                          color: context.tokens.goldInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9)),
                  const SizedBox(height: 6),
                  Text(isFree ? l.auPlanFree : _titleCase(tierRaw),
                      style: text.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 9),
                  _PlanPerk(
                    icon: hasEdits ? Icons.check : Icons.lock_outline,
                    label: l.dashFeatureUnlimitedEdits,
                    faint: !hasEdits,
                  ),
                  _PlanPerk(
                    icon: hasVault ? Icons.check : Icons.lock_outline,
                    label: l.dashFeatureEncryptedVault,
                    faint: !hasVault,
                  ),
                  _PlanPerk(
                    icon: isPremiumPlus ? Icons.check : Icons.lock_outline,
                    label: isPremiumPlus ? l.dashFeatureVideoLegacyUnlocked : l.dashFeatureVideoLegacy,
                    faint: !isPremiumPlus,
                  ),
                  if (!isPremiumPlus) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: OutlinedButton(
                        onPressed: () => context.go('/pricing'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.tokens.goldInk,
                          side: const BorderSide(color: WasiatiColors.brassGold),
                          minimumSize: const Size.fromHeight(40),
                        ),
                        // A free user has no plan to upgrade — they are choosing one.
                        child: Text(isFree ? l.commonSeePlans : l.dashUpgradePremium),
                      ),
                    ),
                  ],
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _PlanPerk extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool faint;
  const _PlanPerk({required this.icon, required this.label, this.faint = false});
  @override
  Widget build(BuildContext context) {
    final color = faint ? context.tokens.faint : context.tokens.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1.5), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 7),
        Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12.5))),
      ]),
    );
  }
}

// --- referral rail (dark) ------------------------------------------------
/// Entry point to the referral programme, rendered as the deep-green rail with a
/// dashed monospace copyable code chip. Without this the programme is unreachable:
/// a user can be referred by a link, but can never share their own.
class _ReferralRail extends ConsumerWidget {
  const _ReferralRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final code = ref.watch(referralSummaryProvider).maybeWhen(data: (s) => s.code, orElse: () => null);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: WasiatiColors.railGreen, borderRadius: BorderRadius.circular(14)),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.workspace_premium_outlined, size: 18, color: WasiatiColors.goldSoft),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 380),
            child: Text(l.dashRefReminder,
                style: const TextStyle(color: WasiatiColors.parchmentLight, fontSize: 12.5, height: 1.5)),
          ),
          if (code != null)
            _RefCodeChip(code: code)
          else
            const WasiatiSkeleton(width: 96, height: 30, radius: 9),
          // The doorway to /referrals — the registered screen with the share
          // link and the earned-credit figures. The rail alone could only COPY
          // a code; the programme's own page was unreachable from anywhere.
          SizedBox(
            height: 44, // >= 44px target (spec §7)
            child: TextButton(
              onPressed: () => context.go('/referrals'),
              style: TextButton.styleFrom(
                foregroundColor: WasiatiColors.goldSoft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.dashRefOpen,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const WasiatiIcon(svg: WasiatiIcons.chevronRight, size: 14, color: WasiatiColors.goldSoft),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefCodeChip extends StatelessWidget {
  final String code;
  const _RefCodeChip({required this.code});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Material(
      color: WasiatiColors.goldSoft.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) WasiatiSnack.success(context, l.refCopied);
        },
        child: DottedBorder(
          color: WasiatiColors.goldSoft,
          radius: 9,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: WasiatiColors.goldSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded dashed 1.5px border, matching the prototype's dashed ref-code chip
/// (Flutter has no built-in dashed border on BoxDecoration).
class DottedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  const DottedBorder({super.key, required this.child, required this.color, this.radius = 9});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashedRectPainter(color: color, radius: radius), child: child);
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color || old.radius != radius;
}

// --- shared bits ---------------------------------------------------------
class _CardMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CardMessage({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: context.tokens.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]);
}

/// The gold Rub-el-Hizb diamond with a parchment check — the wills-summary mark.
class _DiamondCheck extends StatelessWidget {
  final double size;
  final Color fill;
  final Color glyph;
  const _DiamondCheck({required this.size, required this.fill, required this.glyph});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _DiamondCheckPainter(fill, glyph)));
}

class _DiamondCheckPainter extends CustomPainter {
  final Color fill;
  final Color glyph;
  _DiamondCheckPainter(this.fill, this.glyph);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 100);
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -26, 52, 52), const Radius.circular(7));
    final p = Paint()..color = fill;
    canvas.drawRRect(rr, p);
    canvas.save();
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(rr, p);
    canvas.restore();
    final check = Path()
      ..moveTo(-11, 1)
      ..lineTo(-3, 9)
      ..lineTo(12, -9);
    canvas.drawPath(
      check,
      Paint()
        ..color = glyph
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiamondCheckPainter old) => old.fill != fill || old.glyph != glyph;
}

/// A CSS `auto-fit minmax(minItem, 1fr)` grid: chunks [items] into equal-width,
/// equal-height rows sized to the available width.
Widget _flowGrid(BoxConstraints c, List<Widget> items, {required double minItem, required double gap}) {
  if (items.isEmpty) return const SizedBox.shrink();
  final w = c.maxWidth;
  var cols = ((w + gap) / (minItem + gap)).floor();
  if (cols < 1) cols = 1;
  if (cols > items.length) cols = items.length;
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += cols) {
    final row = <Widget>[];
    for (var j = 0; j < cols; j++) {
      if (j > 0) row.add(SizedBox(width: gap));
      final idx = i + j;
      row.add(Expanded(child: idx < items.length ? items[idx] : const SizedBox.shrink()));
    }
    rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: row)));
  }
  return Column(children: [
    for (var r = 0; r < rows.length; r++) ...[
      if (r > 0) SizedBox(height: gap),
      rows[r],
    ],
  ]);
}

bool _confirmed(String status) {
  final s = status.toUpperCase();
  return s == 'CONFIRMED' || s == 'SIGNED';
}

bool _isPremiumPlus(String tier) {
  final t = tier.toUpperCase();
  return t == 'PREMIUM' || t == 'ULTIMATE';
}

String _displayName(String? email) {
  if (email == null || email.isEmpty) return 'friend';
  final local = email.split('@').first;
  final token = local.split(RegExp(r'[._+]')).firstWhere((t) => t.isNotEmpty, orElse: () => local);
  return token.isEmpty ? 'friend' : token[0].toUpperCase() + token.substring(1);
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

({String flag, String code, String currency}) _region(String? region) => switch (region) {
      'KSA' => (flag: '🇸🇦', code: 'KSA', currency: 'SAR'),
      'CA' => (flag: '🇨🇦', code: 'Canada', currency: 'CAD'),
      _ => (flag: '🇺🇸', code: 'US', currency: 'USD'),
    };
