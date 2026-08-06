// Autofill hints are only wired up when an AutofillGroup wraps them.
//
// The owner asked why autofill never appears. Every field was already tagged — email,
// password, newPassword, telephoneNumber, all five address fields — and the app contained
// ZERO AutofillGroup widgets. Flutter only registers fields with the platform autofill
// service (browser password manager, iOS keychain, Android autofill) when they sit inside
// a group; outside one the hints are inert and nothing is ever offered.
//
// That is a silent failure with no error and no visible symptom other than the feature
// simply not happening, which is why it survived: the code reads as though autofill is
// implemented. These tests assert the wiring, not the hints, because the hints were never
// the part that was missing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/widgets/code_cells.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/features/auth/presentation/register_screen.dart';
import 'package:wasiati/features/auth/presentation/forgot_password_screen.dart';
import 'package:wasiati/features/auth/presentation/reset_password_screen.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  // Real metrics, so the auth card's side-by-side social buttons lay out at their true
  // width instead of overflowing by a few pixels on the test's fallback font.
  await load('Fraunces', ['assets/fonts/Fraunces.ttf']);
  await load('Public Sans', ['assets/fonts/PublicSans.ttf']);
  await load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
}

/// A real GoRouter, because RegisterScreen reads GoRouterState in didChangeDependencies
/// (for the ?ref= invite code), ResetPasswordScreen reads the ?token= query, and every auth
/// screen navigates with context.go — a bare `home:` throws "no GoRouterState above this
/// context" before anything renders. [at] can carry a query string.
Future<void> _pumpScreen(WidgetTester t, Widget screen, {String at = '/screen'}) async {
  await _loadFonts();
  t.view.physicalSize = const Size(900, 1500);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in const ['/login', '/register', '/forgot-password', '/verify-phone', '/verify-mfa'])
        GoRoute(path: p, builder: (_, __) => const Scaffold(body: SizedBox.shrink())),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _pumpBare(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  ));
  await t.pumpAndSettle();
}

/// Every field that declares hints must have a group ABOVE it. A hint without an ancestor
/// group is the exact bug this file exists for, so it is asserted per-field rather than by
/// counting groups on the screen. TextFormField builds a TextField internally, so matching
/// TextField catches both.
void _expectHintedFieldsAreGrouped(WidgetTester t) {
  final hinted = find.byWidgetPredicate(
    (w) => w is TextField && (w.autofillHints?.isNotEmpty ?? false),
    description: 'a field declaring autofillHints',
  );
  final count = t.widgetList(hinted).length;
  expect(count, greaterThan(0), reason: 'this screen should declare autofill hints somewhere');

  for (var i = 0; i < count; i++) {
    expect(
      find.ancestor(of: hinted.at(i), matching: find.byType(AutofillGroup)),
      findsAtLeastNWidgets(1),
      reason: 'a hinted field with no AutofillGroup above it is invisible to the password manager',
    );
  }
}

void main() {
  testWidgets('sign-in: the email/password fields sit in an AutofillGroup', (t) async {
    await _pumpScreen(t, const LoginScreen());
    // The form is behind "Continue with email" — the hints do not exist until it is open.
    await t.tap(find.text('Continue with email'));
    await t.pumpAndSettle();

    expect(find.byType(AutofillGroup), findsAtLeastNWidgets(1),
        reason: 'sign-in is the single highest-value autofill surface in the app');
    _expectHintedFieldsAreGrouped(t);
  });

  testWidgets('sign-up: the account and address fields sit in an AutofillGroup', (t) async {
    await _pumpScreen(t, const RegisterScreen());
    expect(find.byType(AutofillGroup), findsAtLeastNWidgets(1),
        reason: 'creating an account is when a password manager most wants to save one');
    _expectHintedFieldsAreGrouped(t);
  });

  testWidgets('forgot-password email step: the email field is grouped', (t) async {
    await _pumpScreen(t, const ForgotPasswordScreen());
    expect(find.byType(AutofillGroup), findsAtLeastNWidgets(1));
    _expectHintedFieldsAreGrouped(t);
  });

  testWidgets('reset-by-link: the new-password field is grouped', (t) async {
    // The screen shows the password form only with a token; without one it renders the
    // "invalid link" state and there is nothing to autofill.
    await _pumpScreen(t, const ResetPasswordScreen(), at: '/screen?token=abc123');
    expect(find.byType(AutofillGroup), findsAtLeastNWidgets(1));
    _expectHintedFieldsAreGrouped(t);
  });

  group('the shared one-time-code field', () {
    Future<void> pumpCode(WidgetTester t) async {
      final controller = TextEditingController();
      final node = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(node.dispose);
      await _pumpBare(
        t,
        Scaffold(
          body: CodeCells(
            controller: controller,
            focusNode: node,
            onCompleted: () {},
            onChanged: () {},
            semanticLabel: 'code',
          ),
        ),
      );
    }

    testWidgets('carries the oneTimeCode hint', (t) async {
      await pumpCode(t);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode),
          reason: 'SMS codes are the one thing every platform autofills for free');
    });

    testWidgets('brings its own group, so all five screens that mount it are wired', (t) async {
      // login MFA, phone verification, password reset, the witness/trustee confirm flow and
      // the heir portal all mount this widget and none of them had a group. Putting it on
      // the widget fixes all five at once — and a one-time code is a self-contained autofill
      // context anyway, sharing nothing with the email or password on the page.
      await pumpCode(t);
      expect(
        find.ancestor(of: find.byType(TextField), matching: find.byType(AutofillGroup)),
        findsOneWidget,
      );
    });
  });
}
