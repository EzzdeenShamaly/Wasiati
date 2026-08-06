import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../commerce/application/entitlement_providers.dart';

/// The entry to will creation (spec §3). Premium/Ultimate choose Ameen (AI) or the
/// guided form; everyone else goes straight to the form. Whichever path, the review
/// and seal are the same — the copy says so, and the user can switch anytime.
///
/// The form itself lives at /wills/new/form. This screen only routes into it.
class WillStartScreen extends ConsumerWidget {
  const WillStartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final entitlement = ref.watch(entitlementProvider);

    // While the entitlement loads we don't yet know if Ameen should be offered.
    // Standard/Basic (or a load error) sees the form directly — never a locked AI
    // path that would 403; the form carries its own soft-sell pill.
    final canAi = entitlementHas(entitlement.valueOrNull, 'aiIntake');
    if (entitlement.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!canAi) {
      // Redirect after this frame so build() stays pure.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/wills/new/form');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        // An explicit destination, not AppBar's automatic leading. The app navigates
        // with go() rather than push(), so the stack is replaced and there is nothing
        // to pop — the automatic back button silently renders as nothing, which is
        // how this screen came to be a dead end.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: context.l10n.wdBackToWills,
          onPressed: () => context.go('/wills'),
        ),
      ),
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            // Padding the content rather than the viewport keeps the two choice cards where
            // they were: the scroll view shrink-wraps to content + bar, so Center offsets them
            // back above the glass. On a short screen the note below them still scrolls clear.
            padding: const EdgeInsets.all(24) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.wsChooseTitle, style: t.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(l.wsChooseSubtitle,
                    style: t.bodyMedium?.copyWith(color: context.tokens.muted), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                _Choice(
                  icon: Icons.auto_awesome,
                  accent: true,
                  title: l.wsAmeenTitle,
                  subtitle: l.wsAmeenSub,
                  badge: l.wsAmeenBadge,
                  verse: l.wsAmeenVerse,
                  onTap: () => context.go('/intake'),
                ),
                const SizedBox(height: 14),
                _Choice(
                  icon: Icons.edit_note_outlined,
                  accent: false,
                  title: l.wsFormTitle,
                  subtitle: l.wsFormSub,
                  meta: l.wsFormMeta,
                  onTap: () => context.go('/wills/new/form'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(l.wsChooseNote,
                        style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4),
                        textAlign: TextAlign.center),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.verse,
    this.meta,
  });
  final IconData icon;
  final bool accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Gold "INCLUDED IN YOUR PLAN" pill on the premium (Ameen) card.
  final String? badge;

  /// Italic gold verse/attribution shown inside the Ameen card.
  final String? verse;

  /// Faint meta line (e.g. "≈ 5 minutes · autosaves as you go") on the form card.
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    // The premium path is the prototype's filled dark "rail" card: bottle-green
    // fill, light title, muted-green subtitle, gold border. The form path stays a
    // plain parchment card.
    final titleColor = accent ? WasiatiColors.parchmentLight : null;
    final subtitleColor = accent ? WasiatiColors.darkTextMuted : context.tokens.muted;
    final iconColor = accent ? WasiatiColors.goldSoft : context.tokens.muted;

    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent ? WasiatiColors.bottleGreen : context.tokens.card,
        borderRadius: BorderRadius.circular(accent ? 20 : 18),
        border: Border.all(color: accent ? WasiatiColors.brassGold : context.tokens.hairline, width: accent ? 1.5 : 1),
      ),
      child: Row(children: [
        Icon(icon, size: 26, color: iconColor),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium?.copyWith(color: titleColor)),
            const SizedBox(height: 4),
            Text(subtitle, style: t.bodySmall?.copyWith(color: subtitleColor, height: 1.4)),
            if (verse != null) ...[
              const SizedBox(height: 8),
              Text(verse!,
                  style: t.bodySmall?.copyWith(
                      color: WasiatiColors.goldSoft, fontStyle: FontStyle.italic, height: 1.4)),
            ],
            if (meta != null) ...[
              const SizedBox(height: 8),
              Text(meta!, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
            ],
          ]),
        ),
        Icon(rtl ? Icons.chevron_left : Icons.chevron_right,
            color: accent ? WasiatiColors.darkTextMuted : context.tokens.faint),
      ]),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(accent ? 20 : 18),
      onTap: onTap,
      child: badge == null
          ? card
          : Stack(clipBehavior: Clip.none, children: [
              card,
              PositionedDirectional(
                top: -10,
                end: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    // goldDeep, not brassGold: a light label on raw brassGold is 3.30:1.
                    // Same pairing WasiatiButtons.goldSolid settled on (colors.dart).
                    color: WasiatiColors.goldDeep,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(badge!,
                      style: const TextStyle(
                          color: WasiatiColors.parchmentLight,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6)),
                ),
              ),
            ]),
    );
  }
}
