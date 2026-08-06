import 'package:flutter/material.dart';
import 'colors.dart';
import 'wasiati_icons.dart';

/// The prototype's light/dark theme switch — the single control the app presents
/// everywhere it offers a theme flip (nav rail, auth screens, Settings).
///
/// Geometry is transcribed verbatim from the prototype's `toggleTheme` markup:
///
/// ```html
/// <span style="width:30px;height:16px;border-radius:99px;background:{{knobTrack}};">
///   <span style="top:2px;inset-inline-start:{{knobPos}};width:12px;height:12px;
///                border-radius:50%;background:#ECE3D0;transition:inset-inline-start .2s;">
///     <!-- light --> <svg width="8" height="8" stroke="#A87B33" stroke-width="2.6">…sun…
///     <!-- dark  --> <svg width="8" height="8" fill="#1C2333">…moon…
/// ```
/// with `knobTrack: dark ? '#C9A45E' : 'rgba(236,227,208,.22)'` and
/// `knobPos: dark ? '16px' : '2px'`.
///
/// The knob travel falls out of the geometry rather than being hard-coded: a 12px
/// knob inset 2px inside a 30px track sits at 2px (start) and 16px (end), which is
/// exactly the prototype's two positions. `inset-inline-start` is the *logical*
/// edge, so the knob slides toward the right in RTL — [AlignmentDirectional] keeps
/// that behaviour without a Directionality check here.
///
/// ### Why [onDarkField] exists
/// The prototype only ever mounts this pill on the deep-green rail, so its OFF
/// track is `parchment @ 22%` — a parchment veil that reads only against green.
/// Dropped verbatim onto the auth screen or a Settings card (both parchment in
/// light mode) that track measures 1.02:1: an invisible control. Nor does the knob
/// rescue it — it is parchment too, 1.11:1 against a parchment card, where on the
/// rail its silhouette alone is 9.79:1.
///
/// So off the rail the track is the only thing left to identify the control, and
/// it gets an ink veil at the alpha that clears WCAG 1.4.11's 3:1 against both
/// light fields the pill is mounted on (3.41:1 on a card, 3.30:1 on the parchment
/// background). The ON track is gold and reads against anything, and OFF only ever
/// renders in light mode, so this is the only value that changes. On the rail —
/// the placement the prototype actually drew — every colour is still its own.
class WasiatiThemePill extends StatelessWidget {
  /// Whether the app is currently dark — drives the knob position and the glyph.
  final bool dark;

  /// Flip the theme. Fires on tap anywhere in the (48×48) hit area.
  final VoidCallback onTap;

  /// True when the pill sits on a permanently dark field (the bottle-green nav
  /// rail), which is the case the prototype's own colours were drawn for. False —
  /// the default — when it sits on the themed page surface (auth, Settings).
  final bool onDarkField;

  /// Tooltip + screen-reader label. The caller owns this because only it has the
  /// localizations; passing the *action* ("Dark mode") reads better than the state.
  final String? semanticLabel;

  const WasiatiThemePill({
    super.key,
    required this.dark,
    required this.onTap,
    this.onDarkField = false,
    this.semanticLabel,
  });

  // --- Prototype geometry (logical px) ---------------------------------------
  static const _trackW = 30.0;
  static const _trackH = 16.0;
  static const _knob = 12.0;
  static const _inset = 2.0; // → knob rests at 2px / 16px, per `knobPos`
  static const _glyph = 8.0;
  static const _radius = 99.0;

  /// `transition: inset-inline-start .2s` — CSS's default `ease` timing.
  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    // OFF track: the prototype's exact parchment veil on the green rail; an ink
    // veil at 3:1 on light surfaces, where a parchment one would vanish and the
    // parchment knob cannot identify the control on its own.
    final offTrack = onDarkField
        ? WasiatiColors.parchment.withValues(alpha: 0.22)
        : WasiatiColors.inkNavy.withValues(alpha: 0.54);

    final pill = Container(
      width: _trackW,
      height: _trackH,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.goldDeepDark : offTrack,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: AnimatedAlign(
        duration: _duration,
        curve: Curves.ease,
        alignment: dark ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          width: _knob,
          height: _knob,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: WasiatiColors.parchment, shape: BoxShape.circle),
          child: WasiatiIcon(
            svg: dark ? WasiatiIcons.moon : WasiatiIcons.sun,
            size: _glyph,
            // Both marks ride a parchment knob, so they keep the prototype's own
            // colours in either placement: gold sun, ink moon.
            color: dark ? WasiatiColors.inkNavy : WasiatiColors.brassGold,
          ),
        ),
      ),
    );

    return Semantics(
      label: semanticLabel,
      toggled: dark,
      child: Tooltip(
        message: semanticLabel ?? '',
        // A 30×16 pill is far under the 48×48 minimum touch target, so the visual
        // stays exact and the hit area grows around it.
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          containedInkWell: false,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(child: pill),
          ),
        ),
      ),
    );
  }
}
