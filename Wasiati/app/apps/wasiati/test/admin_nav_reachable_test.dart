import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/shell/app_shell.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// /admin/content was routed since the Content editor landed and reachable ONLY
/// by typing the URL — no rail entry, no link, nothing. Same class of bug as the
/// unreachable /referrals (see entry_points_reachable_test.dart): a registered
/// route is not a shipped feature until something navigates to it. These pin the
/// admin rail entries for Content and Burial quotes, and that they actually GO.
class _AdminAuth extends AuthController {
  @override
  AuthState build() =>
      const AuthSignedIn(AuthUser(id: 'a1', email: 'admin@wasiati.com', role: 'ADMIN', region: 'US'));
}

class _UserAuth extends AuthController {
  @override
  AuthState build() =>
      const AuthSignedIn(AuthUser(id: 'u1', email: 'user@x.com', role: 'USER', region: 'US'));
}

Future<void> _pump(WidgetTester t, {required AuthController Function() auth}) async {
  // Wide enough for the 230px rail (>=900 breakpoint).
  t.view.physicalSize = const Size(1400, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(initialLocation: '/dashboard', routes: [
    for (final path in ['/dashboard', '/admin/content', '/admin/burial-quotes'])
      GoRoute(
        path: path,
        // Marker child, not the real screen: the routes themselves are already
        // registered in app_router — what was missing (and is under test) is the
        // NAVIGATION to them.
        builder: (_, s) => AppShell(location: s.uri.path, child: Text('at:${s.uri.path}')),
      ),
  ]);

  await t.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(auth)],
    child: MaterialApp.router(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  late AppLocalizations l;
  setUpAll(() async => l = await AppLocalizations.delegate.load(const Locale('en')));

  testWidgets("the admin rail's Content entry actually navigates to /admin/content", (t) async {
    await _pump(t, auth: _AdminAuth.new);

    await t.ensureVisible(find.text(l.navAdminContent));
    await t.tap(find.text(l.navAdminContent));
    await t.pumpAndSettle();

    expect(find.text('at:/admin/content'), findsOneWidget,
        reason: '/admin/content was reachable only by typing the URL — the rail '
            'entry must genuinely navigate, not merely render.');
  });

  testWidgets("the admin rail's Burial quotes entry actually navigates", (t) async {
    await _pump(t, auth: _AdminAuth.new);

    await t.ensureVisible(find.text(l.navBurialQuotes));
    await t.tap(find.text(l.navBurialQuotes));
    await t.pumpAndSettle();

    expect(find.text('at:/admin/burial-quotes'), findsOneWidget);
  });

  testWidgets('a non-admin sees neither entry', (t) async {
    await _pump(t, auth: _UserAuth.new);

    expect(find.text(l.navAdminContent), findsNothing);
    expect(find.text(l.navBurialQuotes), findsNothing);
  });
}
