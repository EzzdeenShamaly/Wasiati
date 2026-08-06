import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/features/auth/presentation/register_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// A new user must be able to reach sign-up FROM the app, not only from the landing
/// page's "Start my will" CTA.
///
/// This regressed once already: the link was removed on the reasoning that the DV2.1
/// prototype's auth block shows no "Create one" affordance. That is true of the
/// prototype, but it left anyone who opens the app directly, bookmarks /login, or taps
/// Sign in before realising they need an account with no route to /register anywhere in
/// the auth flow. The owner reported it as "missing a sign up page". If prototype
/// fidelity is ever cited to remove it again, this test should fail first and force the
/// dead end to be considered explicitly.
Future<void> _pump(WidgetTester t, Widget screen, {String initial = '/'}) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/', builder: (_, __) => screen),
          GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
          GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        ],
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('login offers a route to sign-up', (t) async {
    await _pump(t, const LoginScreen());
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.text(l.authNoAccountCreate),
      findsOneWidget,
      reason: 'A new user landing on /login has no other way to create an account.',
    );
  });

  testWidgets('tapping it actually lands on the register screen', (t) async {
    await _pump(t, const LoginScreen());
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    // Presence is not enough — the control must genuinely navigate.
    await t.tap(find.text(l.authNoAccountCreate));
    await t.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('register still offers the way back, so the pair is not a trap', (t) async {
    await _pump(t, const RegisterScreen());
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await t.tap(find.text(l.authHaveAccountSignIn));
    await t.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
