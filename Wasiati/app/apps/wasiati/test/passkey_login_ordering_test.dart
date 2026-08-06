import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// A device that already holds a passkey should be offered it FIRST.
///
/// Not cosmetic. A password sign-in always costs an OTP; a passkey sign-in is the one
/// exempt path. So a returning user who reaches for the password out of habit keeps paying
/// for a text on every login, having already done the work of enrolling — the free method
/// has to be the obvious one, and obvious means first.
///
/// These also guard the ordering's two failure modes, which are both easy to reintroduce:
/// showing the button TWICE (promoted plus fallback), and the async preference read that
/// once left a pending timer and broke eight unrelated suites (now handled globally by
/// test/flutter_test_config.dart).
Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(initialLocation: '/', routes: [
        GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
      ]),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  const passkeyLabel = 'Continue with passkey';
  const emailLabel = 'Continue with email';

  testWidgets('a device WITH a passkey sees it above the email option', (t) async {
    SharedPreferences.setMockInitialValues({'passkey_on_this_device_v1': true});
    await _pump(t);

    final passkey = find.text(passkeyLabel);
    final email = find.text(emailLabel);
    expect(passkey, findsOneWidget, reason: 'promoted, and never rendered twice');
    expect(email, findsOneWidget);
    expect(
      t.getTopLeft(passkey).dy,
      lessThan(t.getTopLeft(email).dy),
      reason: 'the free sign-in method must be the one they reach for first',
    );
  });

  testWidgets('a device with NO passkey still offers one, just not promoted', (t) async {
    // The fallback matters: this is how a NEW device enrols in the first place, and how
    // someone with a synced keychain passkey discovers they can use it here.
    SharedPreferences.setMockInitialValues({});
    await _pump(t);
    expect(find.text(passkeyLabel), findsOneWidget);
  });

  testWidgets('an unreadable preference degrades to not-promoted, never to a crash', (t) async {
    // A value of the wrong TYPE is what a future rename or a corrupted store looks like.
    // It must read as "unknown", which is the safe default — the button still exists.
    SharedPreferences.setMockInitialValues({'passkey_on_this_device_v1': 'yes'});
    await _pump(t);
    expect(find.text(passkeyLabel), findsOneWidget);
  });
}
