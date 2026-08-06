import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../features/auth/domain/auth_state.dart';
import '../l10n/l10n.dart';
import '../providers.dart';
import '../theme/theme_mode_provider.dart';

class _Dest {
  /// A [WasiatiIcons] SVG glyph, or null when the glyph has no catalogue entry
  /// and [fallback] (a Material [IconData]) should be rendered instead.
  final String? svg;
  final IconData? fallback;
  final String label;
  final String path;
  const _Dest(this.svg, this.label, this.path, {this.fallback});

  /// Renders the destination glyph. Active/selected state is expressed purely
  /// through [color] (gold vs idle); WasiatiIcon has no separate filled variant.
  /// When [color] is null the icon inherits the ambient IconTheme (used by the
  /// bottom NavigationBar so its own selected/unselected animation drives colour).
  Widget buildIcon({double size = 22, Color? color}) => svg != null
      ? WasiatiIcon(svg: svg!, size: size, color: color)
      : Icon(fallback, size: size, color: color);
}

/// Destinations are built per-frame so labels follow the active locale.
List<_Dest> _primaryDests(AppLocalizations l) => [
      _Dest(WasiatiIcons.home, l.navHome, '/dashboard'),
      _Dest(WasiatiIcons.wills, l.navWills, '/wills'),
      _Dest(WasiatiIcons.vault, l.navVault, '/vault'),
      _Dest(WasiatiIcons.burial, l.navBurial, '/burial'),
      _Dest(WasiatiIcons.guided, l.navGuided, '/intake'),
      // Legacy (video/voice messages) lives inside a will now — see _LegacyLink in
      // will_detail_screen — so it is intentionally not a top-level nav destination.
      _Dest(WasiatiIcons.identity, l.navIdentity, '/kyc'),
      _Dest(WasiatiIcons.plans, l.navPlans, '/pricing'),
    ];
List<_Dest> _adminDestsFor(AppLocalizations l) => [
      _Dest(WasiatiIcons.admin, l.navAdmin, '/admin'),
      _Dest(WasiatiIcons.users, l.navUsers, '/admin/users'),
      _Dest(WasiatiIcons.claims, l.navClaims, '/admin/death-claims'),
      // The DV2.1 admin console's Content tab. The copy-editor glyph has no
      // catalogue entry, so the pencil stands in for it.
      _Dest(WasiatiIcons.edit, l.navAdminContent, '/admin/content'),
      _Dest(WasiatiIcons.burial, l.navBurialQuotes, '/admin/burial-quotes'),
    ];

/// Persistent responsive navigation around the signed-in app: the designed
/// 230px bottle-green rail on wide screens (gold active bar + icon, brand header,
/// sign-out + theme switch at the bottom), a bottom NavigationBar (+ "More" sheet)
/// on narrow ones. Screens keep their own AppBars/FABs; this shell owns navigation.
class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;
  const AppShell({super.key, required this.location, required this.child});

  // v2.2 rail: deep green field, gold icon accent (brighter than brassGold here).
  static const _railBg = WasiatiColors.railGreen;
  static const _gold = WasiatiColors.railIcon;
  static final _activeFill = WasiatiColors.parchment.withValues(alpha: 0.14);
  static final _idle = WasiatiColors.onDark.withValues(alpha: 0.72);
  static final _hairline = WasiatiColors.parchment.withValues(alpha: 0.12);

  bool _isActive(String path) => location == path || location.startsWith('$path/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth is AuthSignedIn && auth.user.role == 'ADMIN';
    final dests = [..._primaryDests(l), if (isAdmin) ..._adminDestsFor(l)];
    final wide = MediaQuery.sizeOf(context).width >= 900;

    // The routed page, made selectable. Flutter paints to a canvas on web, so ordinary
    // Text has no native selection unless a SelectionArea wraps it — the owner reported not
    // being able to select anything. Wrapping the page BODY (not the rail/bottom-nav) leaves
    // the chrome unselectable while every screen's content becomes selectable and copyable;
    // text fields keep their own EditableText selection. Placed here, and in AuthScaffold
    // for the signed-out screens, because SelectionArea needs the router's Overlay as an
    // ancestor — which exists below the Navigator but not at the MaterialApp builder.
    final page = SelectionArea(child: child);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _rail(context, ref, l, dests),
          Expanded(child: page),
        ]),
      );
    }

    // Narrow: bottom nav with the first four + a More overflow.
    final primary = dests.take(4).toList();
    // "More" has no catalogue glyph, so it falls back to the Material overflow icon.
    final navItems = [...primary, _Dest(null, l.navMore, '__more__', fallback: Icons.more_horiz)];
    var selected = primary.indexWhere((d) => _isActive(d.path));
    if (selected < 0) selected = navItems.length - 1;

    return Scaffold(
      // Lets the page paint the full height, so the frosted bar has live content to
      // blur rather than a dead strip. Scaffold hands the bar's height to the body as
      // MediaQuery.padding.bottom, and screens must spend it on their scrolled
      // CONTENT — SafeArea(bottom: false) plus that much scroll padding. Spending it
      // on the VIEWPORT instead (a plain SafeArea) stops content dead at the bar's top
      // edge, and the glass ends up blurring a flat scaffold.
      extendBody: true,
      body: page,
      bottomNavigationBar: _GlassBar(
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final on = states.contains(WidgetState.selected);
              return TextStyle(
                fontFamily: WasiatiType.bodyFamily,
                fontSize: 11.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? context.tokens.goldInk : context.tokens.muted,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: selected.clamp(0, navItems.length - 1),
            // The glass supplies the tint; the NavigationBar on top of it must be
            // fully transparent or M3 paints an opaque surface over the blur.
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            indicatorColor: WasiatiColors.brassGold.withValues(alpha: 0.16),
            onDestinationSelected: (i) {
              if (i == navItems.length - 1) {
                _showMore(context, ref, dests.skip(4).toList());
              } else {
                context.go(navItems[i].path);
              }
            },
            destinations: [
              for (final d in navItems)
                NavigationDestination(
                  // Coloured explicitly rather than left to the bar's own
                  // selected/unselected animation: WasiatiIcon resolves a null colour
                  // off the ambient DefaultTextStyle *before* IconTheme, so inheriting
                  // here is at the mercy of whatever text style is in scope.
                  icon: d.buildIcon(size: 24, color: context.tokens.muted),
                  selectedIcon: d.buildIcon(size: 24, color: context.tokens.goldInk),
                  label: d.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The designed 230px bottle-green rail.
  Widget _rail(BuildContext context, WidgetRef ref, AppLocalizations l, List<_Dest> dests) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The rail sits on the leading edge, so keep the OUTER (screen-edge) safe-area inset
    // and drop the INNER one. In RTL the rail moves to the right, so the sides flip —
    // SafeArea takes physical sides, so derive them from the text direction.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      width: 230,
      color: _railBg,
      // The rail's ornament layer paints between the green field and the nav
      // items (CustomPaint runs `painter` before `child`), so it reads as
      // tooling on the surface rather than as a veil over the labels.
      child: CustomPaint(
        painter: _RailOrnamentPainter(),
        child: SafeArea(
          left: !isRtl,
          right: isRtl,
          child: Column(children: [
            // Brand header — the prototype's bilingual rail lockup: seal · "Wasiati"
            // stacked over وصيتي in gold. The Arabic line is the mark's calligraphic
            // half and was missing from the app entirely on this surface; the
            // prototype renders it at `font-family:'IBM Plex Sans Arabic';
            // font-size:10.5px; color:#C9A45E` directly beneath the Latin wordmark
            // (Prototype `data-el="rail"`). It is brand artwork, not copy, so it is
            // a literal here exactly as in WasiatiWordmark — never localized.
            const Padding(
              padding: EdgeInsetsDirectional.fromSTEB(20, 22, 20, 16),
              child: Row(children: [
                Seal(size: 30, status: SealStatus.verified),
                SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Wasiati',
                          style: TextStyle(
                            fontFamily: WasiatiType.displayFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: WasiatiColors.onDark,
                            letterSpacing: -0.2,
                            height: 1.15,
                          )),
                      Text('وصيتي',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: WasiatiType.arabicFamily,
                            fontSize: 12,
                            // goldDeepDark is the prototype's #C9A45E — the rail is
                            // bottle green in BOTH themes, so this is flat, not a
                            // theme-swapped ink.
                            color: WasiatiColors.goldDeepDark,
                            height: 1.5,
                          )),
                    ],
                  ),
                ),
              ]),
            ),
            // Destinations
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final d in dests)
                    _railItem(d, active: _isActive(d.path), onTap: () => context.go(d.path)),
                ]),
              ),
            ),
            Divider(height: 1, thickness: 1, color: _hairline),
            const SizedBox(height: 4),
            _railItem(
              _Dest(WasiatiIcons.settings, l.navSettings, '/settings'),
              active: _isActive('/settings'),
              onTap: () => context.go('/settings'),
            ),
            // Sign out + theme switch at the very bottom.
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 12, 10),
              child: Row(children: [
                Expanded(
                  child: _railItem(
                    _Dest(WasiatiIcons.signOut, l.commonSignOut, '__signout__'),
                    active: false,
                    onTap: () => ref.read(authControllerProvider.notifier).logout(),
                  ),
                ),
                WasiatiThemePill(
                  dark: dark,
                  // The rail is bottle green in both themes — the one place the
                  // prototype's own parchment-veil off-track was drawn for.
                  onDarkField: true,
                  semanticLabel: dark ? l.settingsThemeLight : l.settingsThemeDark,
                  onTap: () => ref.read(themeModeProvider.notifier).toggle(MediaQuery.platformBrightnessOf(context)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _railItem(_Dest d, {required bool active, required VoidCallback onTap}) {
    final labelColor = active ? WasiatiColors.onDark : _idle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active ? _activeFill : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            if (active)
              PositionedDirectional(
                start: 0,
                top: 9,
                bottom: 9,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(99)),
                ),
              ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 12, 11),
              child: Row(children: [
                d.buildIcon(size: 19, color: active ? _gold : _idle),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(d.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: WasiatiType.bodyFamily,
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: labelColor,
                      )),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _showMore(BuildContext context, WidgetRef ref, List<_Dest> more) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      // The sheet is frosted like the bar it rises from, so the theme's opaque
      // card colour has to come off it — otherwise it paints over the blur.
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => _GlassSheet(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final d in more)
            ListTile(
              leading: d.buildIcon(size: 24, color: ctx.tokens.muted),
              title: Text(d.label),
              onTap: () {
                Navigator.pop(ctx);
                context.go(d.path);
              },
            ),
          Divider(height: 1, color: ctx.tokens.hairline),
          ListTile(
            leading: WasiatiIcon(svg: WasiatiIcons.settings, size: 24, color: ctx.tokens.muted),
            title: Text(l.navSettings),
            onTap: () {
              Navigator.pop(ctx);
              context.go('/settings');
            },
          ),
          ListTile(
            leading: WasiatiIcon(svg: WasiatiIcons.signOut, size: 24, color: ctx.tokens.muted),
            title: Text(l.commonSignOut),
            onTap: () {
              Navigator.pop(ctx);
              ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ]),
      ),
    );
  }
}

/// The rail's geometric ornament — the prototype's gold hexagon rosettes, bled
/// off the rail's edges and clipped by it.
///
/// Transcribed from `data-el="rail"` in the prototype, which renders four
/// `data-decor="hex"` SVGs behind the nav items whenever `showHexDecor` is on
/// (its default) at `hexPlacement: 'edges'` (also its default). Each is the same
/// mark: a regular hexagon in a 100-unit box, stroked `#C9A45E` at 2, with a
/// second copy of itself rotated 30° at 1 — the six-point rosette. The app had
/// the rail's colour and geometry but none of its artwork.
///
/// Flat gold rather than a theme-swapped ink: the rail is bottle green in both
/// themes, so there is no light end to choose. The whole layer sits at ~.16
/// opacity, well under the 3:1 boundary bar, because it is decoration — nothing
/// is read on it and nothing is operated by it.
class _RailOrnamentPainter extends CustomPainter {
  // (left, top, width, height, degrees, opacity) exactly as the prototype's
  // inline styles give them, in the rail's own 230px-wide coordinate space.
  static const _hexes = <(double, double, double, double, double, double)>[
    (119, -63, 190, 190, 9, 0.17),
    (98, 414, 342, 280, 9, 0.17),
    (-179, 178, 295, 248, 18, 0.16),
    (-102, 669, 232, 271, 18, 0.16),
  ];

  static final Path _hexPath = () {
    // polygon points="50,5 89,27.5 89,72.5 50,95 11,72.5 11,27.5"
    const pts = [
      Offset(50, 5),
      Offset(89, 27.5),
      Offset(89, 72.5),
      Offset(50, 95),
      Offset(11, 72.5),
      Offset(11, 27.5),
    ];
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (left, top, w, h, deg, opacity) in _hexes) {
      canvas.save();
      // CSS `transform: rotate()` turns about the element's own centre.
      canvas.translate(left + w / 2, top + h / 2);
      canvas.rotate(deg * math.pi / 180);
      canvas.scale(w / 100, h / 100);
      canvas.translate(-50, -50);
      final paint = Paint()
        ..color = WasiatiColors.goldDeepDark.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(_hexPath, paint);
      canvas.save();
      canvas.translate(50, 50);
      canvas.rotate(math.pi / 6); // rotate(30 50 50)
      canvas.translate(-50, -50);
      canvas.drawPath(_hexPath, paint..strokeWidth = 1);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RailOrnamentPainter oldDelegate) => false;
}

/// The frosted "Apple glass" treatment shared by the mobile nav bar and its
/// "More" sheet: real backdrop blur, a low-opacity brand tint over it, and a
/// hairline edge.
///
/// The tint is what keeps this legible rather than merely pretty — blur alone
/// leaves whatever scrolls underneath showing through at full contrast, so nav
/// labels start fighting body text. At ~0.72 the brand surface reads as frosted
/// while flattening the content behind it to a wash.
abstract final class _Glass {
  static const sigma = 20.0; // within the 18–24 the design calls for
  static const tintAlpha = 0.72;

  static Color tint(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The card colour, not the scaffold's: the bar reads as a raised surface
    // floating over the page in both themes.
    return (dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentLight)
        .withValues(alpha: tintAlpha);
  }
}

/// Frosted mobile navigation bar — blurs the page scrolling beneath it.
class _GlassBar extends StatelessWidget {
  final Widget child;
  const _GlassBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // Without the clip the filter samples (and smears) the whole screen.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _Glass.sigma, sigmaY: _Glass.sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _Glass.tint(context),
            border: Border(top: BorderSide(color: context.tokens.hairline)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted "More" sheet — the same glass, rounded to the card radius and with a
/// grab handle.
class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  static const _radius = Radius.circular(18);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: _radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _Glass.sigma, sigmaY: _Glass.sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _Glass.tint(context),
            border: Border(top: BorderSide(color: context.tokens.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.tokens.faint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              child,
            ]),
          ),
        ),
      ),
    );
  }
}

