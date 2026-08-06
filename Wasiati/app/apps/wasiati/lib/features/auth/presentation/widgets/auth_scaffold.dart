import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/theme_mode_provider.dart';

/// Shared centered, max-width layout for auth screens with the Seal header and a
/// "‹ Back" link, matching the prototype's auth card (no app bar, no trust strip).
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SealStatus seal;
  final List<Widget> children;
  final bool showBack;

  /// Shows the Wasiati seal in the header. The prototype's MFA card has no seal,
  /// so that screen opts out.
  final bool showSeal;

  /// Overrides what the "‹ Back" link does. Defaults to popping (or going to the
  /// app root). The sign-in screen points it at the marketing landing site, which
  /// lives outside the app.
  final VoidCallback? onBack;

  /// Centers the seal + title + subtitle (the sign-in card look). Full-width
  /// buttons in [children] still stretch — only the header is centered.
  final bool centered;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.seal = SealStatus.locked,
    required this.children,
    this.showBack = true,
    this.showSeal = true,
    this.onBack,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = context.tokens.muted;
    final faint = context.tokens.faint;

    final header = <Widget>[
      if (showSeal) ...[
        Align(
          alignment: centered ? Alignment.center : AlignmentDirectional.centerStart,
          child: WasiatiSeal(size: centered ? 40 : 56),
        ),
        const SizedBox(height: 18),
      ],
      Text(title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: centered ? text.headlineSmall : text.headlineMedium),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: text.bodyMedium?.copyWith(color: muted)),
      ],
      const SizedBox(height: 28),
      ...children,
    ];

    final backLink = showBack
        ? Center(
            child: TextButton.icon(
              onPressed: onBack ?? (() => context.canPop() ? context.pop() : context.go('/')),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: Text(context.l10n.commonBack),
              style: TextButton.styleFrom(foregroundColor: faint),
            ),
          )
        : null;

    // The centered sign-in card floats on the background (parchment surface, r18,
    // soft shadow) with the ‹ Back link beneath it, exactly like the prototype.
    final Widget body = centered
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              decoration: BoxDecoration(
                color: context.tokens.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.tokens.hairline),
                boxShadow: [
                  BoxShadow(color: WasiatiColors.inkNavy.withValues(alpha: 0.14), blurRadius: 60, offset: const Offset(0, 24)),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header),
            ),
            if (backLink != null) ...[const SizedBox(height: 16), backLink],
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...header,
            if (backLink != null) ...[const SizedBox(height: 20), backLink],
          ]);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // SelectionArea so text on the signed-out screens (region notices, verse,
            // helper copy) is selectable too — the same reason as AppShell. It wraps the
            // content, not the theme toggle, and sits below the router's Overlay.
            Center(
              child: SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: body),
                ),
              ),
            ),
            // Light/dark toggle, top-right — so the theme is switchable before sign-in
            // too (the signed-in app has it in the rail + Settings).
            const PositionedDirectional(top: 2, end: 6, child: _AuthThemeToggle()),
          ],
        ),
      ),
    );
  }
}

/// The prototype's theme pill, for the auth screens.
class _AuthThemeToggle extends ConsumerWidget {
  const _AuthThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return WasiatiThemePill(
      dark: dark,
      // Auth sits on the page surface (parchment in light), not the green rail.
      semanticLabel: dark ? context.l10n.settingsThemeLight : context.l10n.settingsThemeDark,
      onTap: () => ref.read(themeModeProvider.notifier).toggle(MediaQuery.platformBrightnessOf(context)),
    );
  }
}

/// Runs an async auth action with a busy flag and surfaces errors via SnackBar.
Future<bool> runAuthAction(
  BuildContext context,
  Future<void> Function() action, {
  void Function()? onError,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final fallback = context.l10n.authGenericError;
  try {
    await action();
    return true;
  } catch (e) {
    final msg = e is ApiException ? e.message : fallback;
    messenger.showSnackBar(SnackBar(
      backgroundColor: WasiatiColors.danger,
      content: Text(msg, style: const TextStyle(color: WasiatiColors.onDark)),
    ));
    onError?.call();
    return false;
  }
}
