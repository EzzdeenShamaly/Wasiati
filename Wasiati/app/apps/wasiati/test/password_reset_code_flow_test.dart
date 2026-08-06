import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/presentation/forgot_password_screen.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The reset-code backend (151714a) shipped while the app still called the LINK
/// endpoint. These tests walk the whole flow — email -> 6-digit code -> new
/// password — and assert each step genuinely reaches its endpoint method with
/// the right arguments; the reset-code service was itself once "complete" with
/// no route exposing it, so a rendered label proves nothing here.
class _RecordingAuthApi extends AuthApi {
  _RecordingAuthApi() : super(Dio());
  final forgotCodeCalls = <String>[];
  final resetCalls = <(String, String, String)>[];

  @override
  Future<void> forgotPasswordCode(String email) async => forgotCodeCalls.add(email);

  @override
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async =>
      resetCalls.add((email, code, newPassword));
}

Future<_RecordingAuthApi> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _RecordingAuthApi();
  await t.pumpWidget(ProviderScope(
    overrides: [authApiProvider.overrideWithValue(api)],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(initialLocation: '/forgot-password', routes: [
        GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ]),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('email -> code -> password: every step reaches its endpoint', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    // Step 1: email. The button must hit POST /auth/password/forgot-code, not
    // the old link endpoint.
    await t.enterText(find.byType(TextField), 'user@wasiati.test');
    await t.tap(find.text(l.forgotSendCode));
    await t.pumpAndSettle();
    expect(api.forgotCodeCalls, ['user@wasiati.test']);

    // Step 2: the code cells (channel-neutral copy — the backend never says
    // where the code went, so the screen must not pretend to know).
    expect(find.text(l.forgotCodeSentBody('user@wasiati.test')), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '654321');
    await t.pumpAndSettle();

    // Step 3: new password, then the single reset call carrying all three.
    await t.enterText(find.byType(TextField).first, 'brand-new-password');
    await t.tap(find.text(l.resetSubmit));
    await t.pumpAndSettle();
    expect(api.resetCalls, [('user@wasiati.test', '654321', 'brand-new-password')],
        reason: 'The submit must genuinely POST /auth/password/reset-code with the '
            'email, the typed code and the new password.');

    // Lands back on sign-in.
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a short password is rejected locally and nothing is sent', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.enterText(find.byType(TextField), 'user@wasiati.test');
    await t.tap(find.text(l.forgotSendCode));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '654321');
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).first, 'short');
    await t.tap(find.text(l.resetSubmit));
    await t.pumpAndSettle();

    expect(find.text(l.resetValidator), findsOneWidget);
    expect(api.resetCalls, isEmpty);
  });

  testWidgets('the resend control re-requests a code for the same address', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.enterText(find.byType(TextField), 'user@wasiati.test');
    await t.tap(find.text(l.forgotSendCode));
    await t.pumpAndSettle();

    // Run the 30s countdown out, then resend.
    await t.pump(const Duration(seconds: 31));
    await t.tap(find.text(l.mfaResend));
    await t.pumpAndSettle();

    expect(api.forgotCodeCalls, ['user@wasiati.test', 'user@wasiati.test'],
        reason: 'Resend must actually re-hit /auth/password/forgot-code — the MFA '
            'screen\'s resend restarts only the timer, and this one must not '
            'inherit that.');
  });
}
