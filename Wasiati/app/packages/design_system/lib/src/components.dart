import 'package:flutter/material.dart';
import 'colors.dart';
import 'seal.dart';
import 'tokens.dart';

// ============================================================================
// Card — the parchment/night surface used across every screen. Fill + border
// resolve from WasiatiTokens so it tracks light/dark; radius defaults to the
// design spec (r18). Replaces the per-screen private `_Card` copies.
// ============================================================================
class WasiatiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  /// Override the hairline border (e.g. a danger/gold accent); null = tokens.hairline.
  final Color? borderColor;

  /// When set, the whole card is tappable (with an ink ripple clipped to the radius).
  final VoidCallback? onTap;

  const WasiatiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.radius = 18,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radiusG = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    // The fill + border live on a Material (not a plain Container) so an onTap InkWell's
    // ink ripple paints ABOVE the card fill instead of being hidden behind an opaque
    // Container background. Elevation stays 0, so this is visually identical to the old
    // decorated Container for the (many) non-tappable cards.
    return Container(
      margin: margin,
      child: Material(
        color: context.tokens.card,
        clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
        shape: RoundedRectangleBorder(
          borderRadius: radiusG,
          side: BorderSide(color: borderColor ?? context.tokens.hairline),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

// ============================================================================
// Upgrade prompt — the gold-bordered "this is a paid feature" card shown when a
// gated screen returns a 403. Row: seal · title+body · See-plans button.
// ============================================================================
class WasiatiUpgradePrompt extends StatelessWidget {
  final SealStatus seal;
  final String title;
  final String body;
  final String seePlansLabel;
  final VoidCallback onSeePlans;

  const WasiatiUpgradePrompt({
    super.key,
    this.seal = SealStatus.sealed,
    required this.title,
    required this.body,
    required this.seePlansLabel,
    required this.onSeePlans,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return WasiatiCard(
      padding: const EdgeInsets.all(18),
      radius: 16,
      borderColor: WasiatiColors.goldBorder,
      child: Row(children: [
        Seal(size: 36, status: seal, filled: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: onSeePlans, child: Text(seePlansLabel)),
      ]),
    );
  }
}

// ============================================================================
// Chips — r99. region · ADMIN · COMPED · MOST POPULAR · locked-feature.
// ============================================================================
enum WasiatiChipKind { neutral, region, admin, comped, mostPopular, lockedFeature }

class WasiatiChip extends StatelessWidget {
  final String label;
  final WasiatiChipKind kind;
  final IconData? icon;
  const WasiatiChip(this.label, {super.key, this.kind = WasiatiChipKind.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    late Color bg, fg;
    Color? borderColor;
    switch (kind) {
      case WasiatiChipKind.region:
        // Was the open-coded `dark ? greenDeep : greenTint` / `darkText :
        // bottleGreen` pair; identical values, now read from the tokens that name
        // them (WasiatiTokens.highlight / .greenInk) so every highlighted box in
        // the product moves together.
        bg = context.tokens.highlight;
        fg = context.tokens.greenInk;
      case WasiatiChipKind.admin:
        bg = WasiatiColors.inkNavy;
        fg = WasiatiColors.onDark;
      case WasiatiChipKind.comped:
        // Light field is goldDeep, not brassGold: the onDark label on raw brassGold is
        // 3.22:1, the pairing colors.dart already records as rejected for the gold CTA.
        bg = WasiatiColors.goldDeep;
        fg = dark ? WasiatiColors.darkText : WasiatiColors.onDark;
      case WasiatiChipKind.mostPopular:
        bg = WasiatiColors.goldSoft;
        fg = WasiatiColors.inkNavy;
      case WasiatiChipKind.lockedFeature:
        bg = Colors.transparent;
        fg = dark ? WasiatiColors.goldSoft : WasiatiColors.goldDeep;
        borderColor = fg;
      case WasiatiChipKind.neutral:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: borderColor != null ? Border.all(color: borderColor, width: 1.2) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: kind == WasiatiChipKind.mostPopular || kind == WasiatiChipKind.admin ? 0.6 : 0.2,
          ),
        ),
      ]),
    );
  }
}

// ============================================================================
// Button style helpers (theme covers primary/outlined/text; these add the
// gold "upgrade" solid and the destructive variant from the handoff).
// ============================================================================
abstract final class WasiatiButtons {
  /// The gold "upgrade" CTA. Field and label swap ends of the scale together.
  ///
  /// A fill carrying a label owes the type bar (DECISIONS §14 addendum), and
  /// `brassGold` cannot pay it: `onDark` on `brassGold` is 3.22:1 at labelLarge's
  /// 15px/w600 — too small for the large-text escape — and no permitted ink rescues
  /// it, since `inkNavy`, the darkest in the palette, reaches only 4.15:1 and black
  /// is not a UI colour here. Nor can one fixed gold serve both themes: against a
  /// night card the label needs a field luminance ≤ 0.1483 while the 3:1 boundary
  /// needs ≥ 0.1551, and those do not overlap. So the field takes the two ends
  /// `goldInk` already theme-swaps, and the label inverts with it — parchment on
  /// dark gold in light, ink on light gold in dark. See DECISIONS §15.
  ///
  /// Deliberately the raw constants, not `context.tokens.goldInk`: that token is
  /// tuned as type ON a surface, and this is a field UNDER type. The values coincide
  /// today; the jobs do not.
  static ButtonStyle goldSolid(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ElevatedButton.styleFrom(
      backgroundColor: dark ? WasiatiColors.goldDeepDark : WasiatiColors.goldDeep,
      foregroundColor: dark ? WasiatiColors.inkNavy : WasiatiColors.onDark,
      // Height-only; full width comes from the layout, not an infinite min width.
      minimumSize: const Size(0, 50),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  static ButtonStyle destructive(BuildContext context) => ElevatedButton.styleFrom(
        backgroundColor: WasiatiColors.danger,
        foregroundColor: WasiatiColors.onDark,
        // Height-only; full width comes from the layout, not an infinite min width.
        minimumSize: const Size(0, 50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

// ============================================================================
// Snackbars — success / danger, floating, rounded.
// ============================================================================
abstract final class WasiatiSnack {
  /// The success field is the *darkened* end of the scale, not the raw fill.
  ///
  /// DECISIONS §14 exempts fills from the 4.5:1 type bar — but that holds only for
  /// fills nothing is read on (borders, dots, donut slices). A snackbar is a fill
  /// with a label on it, so it owes the bar twice over: `onDark` on `success` is
  /// 4.24:1, where `successDeep` carries the same label at 4.91:1. `danger` needs
  /// no equivalent move — it already carries `onDark` at 5.72:1.
  static void success(BuildContext context, String message) => _show(context, message, WasiatiColors.successDeep);
  static void danger(BuildContext context, String message) => _show(context, message, WasiatiColors.danger);

  static void _show(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: color,
        content: Text(message, style: const TextStyle(color: WasiatiColors.onDark, fontWeight: FontWeight.w600)),
      ));
  }
}

// ============================================================================
// Back link — the way out of any screen inside a multi-step flow.
//
// Every step of the will workflow must offer one. Browser back is not a
// substitute: the app is also a PWA and an installed shell, where there is no
// browser chrome to fall back on, and a step that can only be left by finishing
// it traps someone who opened it to look.
//
// Deliberately a chevron + label rather than a bare "‹" in the string: the
// glyph flips with the text direction on its own, so Arabic gets a
// right-pointing arrow without a second translated variant.
// ============================================================================
class WasiatiBackLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// Sits flush with the content column by default. Screens that place it
  /// against a card edge can pad it back out.
  final EdgeInsetsGeometry padding;

  const WasiatiBackLink({
    super.key,
    required this.label,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: padding,
        child: TextButton.icon(
          onPressed: onTap,
          // back_ios_new rather than arrow_back: it is the lighter chevron the
          // rest of the product uses for "up one level".
          icon: const Icon(Icons.arrow_back_ios_new, size: 14),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: context.tokens.muted,
            padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 10, 8),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Empty state — idle seal + one line + optional CTA.
// ============================================================================
class WasiatiEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final SealStatus seal;

  const WasiatiEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.seal = SealStatus.idle,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Seal(size: 56, status: seal),
          const SizedBox(height: 20),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: text.bodySmall, textAlign: TextAlign.center),
          ],
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onCta, child: Text(ctaLabel!)),
          ],
        ]),
      ),
    );
  }
}

// ============================================================================
// Skeleton shimmer — parchmentDeep -> parchment sweep for loading states.
// ============================================================================
class WasiatiSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const WasiatiSkeleton({super.key, this.width = double.infinity, this.height = 16, this.radius = 8});

  @override
  State<WasiatiSkeleton> createState() => _WasiatiSkeletonState();
}

class _WasiatiSkeletonState extends State<WasiatiSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentDeep;
    final hi = dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentLight;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t) + 1, 0),
              colors: [base, hi, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
