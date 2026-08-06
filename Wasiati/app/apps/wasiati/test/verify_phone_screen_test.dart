// Signup step 2: the screen that proves the phone.
//
// The endpoints (POST /auth/phone/send-code, /auth/phone/verify) were built, tested and
// verified against the live backend — and nothing in the app called them. So the phone was
// REQUIRED at signup but never actually proved, which is the exact failure mode this repo
// keeps repeating: a working server capability with no screen in front of it.
//
// These drive the real screen and assert on what leaves the app.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/presentation/verify_phone_screen.dart';

class _Api extends AuthApi {
  _Api() : super(Dio());
  int sends = 0;
  final List<String> verified = [];
  bool failVerify = false;
  bool failSend = false;

  @override
  Future<void> sendPhoneCode() async {
    sends++;
    if (failSend) throw ApiException('Too many codes requested. Please wait.', statusCode: 429);
  }

  @override
  Future<void> verifyPhone(String code) async {
    verified.add(code);
    if (failVerify) throw ApiException('That code is incorrect or has expired.', statusCode: 400);
  }
}

/// A real GoRouter, not a bare `home:` — the success path navigates, so a router-less
/// harness would fail on the very case worth proving. It also lets the test assert WHERE
/// the owner ends up rather than just that a request went out.
late GoRouter _router;

Future<_Api> _open(WidgetTester t, {bool failVerify = false, bool failSend = false}) async {
  final api = _Api()
    ..failVerify = failVerify
    ..failSend = failSend;
  _router = GoRouter(
    initialLocation: '/verify-phone',
    routes: [
      GoRoute(path: '/verify-phone', builder: (_, __) => const VerifyPhoneScreen()),
      GoRoute(path: '/dashboard', builder: (_, __) => const Scaffold(body: Text('DASHBOARD'))),
      GoRoute(path: '/passkey-setup', builder: (_, __) => const Scaffold(body: Text('PASSKEY-SETUP'))),
    ],
  );
  addTearDown(_router.dispose);
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [authApiProvider.overrideWithValue(api)],
    child: MaterialApp.router(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return api;
}

Future<void> _enter(WidgetTester t, String code) async {
  await t.enterText(find.byType(EditableText), code);
  await t.pump();
}

void main() {
  // The screen now reads a passkey preference before navigating. Without this the plugin
  // channel never answers in a widget test and getInstance() HANGS, so pumpAndSettle can
  // never settle — this is the plugin's own documented test seam, not a workaround.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a code is sent on arrival, without being asked for', (t) async {
    // The owner was just told a code is coming. Making them press a button for it first
    // would be asking them to request something already promised.
    final api = await _open(t);
    expect(api.sends, 1);
  });

  testWidgets('entering six digits verifies automatically, then offers a passkey', (t) async {
    final api = await _open(t);
    await _enter(t, '123456');
    await t.pump(const Duration(milliseconds: 100));
    expect(api.verified, ['123456'],
        reason: 'the sixth digit submits, so nobody hunts for a button');
    await t.pumpAndSettle();
    // A proved phone hands off to the passkey offer, not the dashboard. That is the moment
    // enrolment converts, and a passkey login is the one path exempt from the OTP — so it
    // is where the whole MFA ladder either pays for itself or does not.
    expect(find.text('PASSKEY-SETUP'), findsOneWidget,
        reason: 'signup offers the free sign-in method once, at the moment people accept');
  });

  testWidgets('but goes straight to the dashboard once that offer has been made', (t) async {
    // Asked once. A security prompt that returns every visit teaches people to dismiss
    // security prompts without reading them.
    SharedPreferences.setMockInitialValues({'passkey_prompt_seen_v1': true});
    final api = await _open(t);
    await _enter(t, '123456');
    await t.pumpAndSettle();
    expect(api.verified, ['123456']);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('a wrong code clears the field for the next attempt', (t) async {
    // Otherwise the owner has to delete six digits by hand before retrying.
    final api = await _open(t, failVerify: true);
    await _enter(t, '000000');
    await t.pump(const Duration(milliseconds: 200));
    expect(api.verified, ['000000']);
    expect(t.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
  });

  testWidgets('a failed FIRST send does not strand the screen', (t) async {
    // The server 429s on the 30s cooldown and the hourly cap. If that left the screen
    // spinning, the owner would have no way forward at all.
    final api = await _open(t, failSend: true);
    expect(api.sends, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the screen must settle into a usable state even when the send failed');
  });

  testWidgets('the resend control is disabled while the countdown runs', (t) async {
    await _open(t);
    final resend = find.byType(TextButton);
    expect(resend, findsOneWidget);
    expect(t.widget<TextButton>(resend).onPressed, isNull,
        reason: 'resending inside the cooldown would only earn a 429');
  });

  testWidgets('the copy explains why the number matters', (t) async {
    await _open(t);
    // Not decoration: people abandon a verification step they think is bureaucracy. This
    // number carries the login factor, the witness invitations and the death-claim lookup.
    expect(find.textContaining('witnesses'), findsOneWidget);
  });
}
