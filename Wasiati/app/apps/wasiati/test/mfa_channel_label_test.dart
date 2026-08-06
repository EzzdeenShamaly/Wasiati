import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/presentation/verify_mfa_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The backend's MFA challenge says which channel the code went out on
/// (`via: sms|email` — phone when there is one, else the email). The screen used
/// to hardcode the SMS wording, so a phoneless user was told to check their
/// texts for a code that had been EMAILED. These tests pin the label to the
/// channel, and that the entered code actually reaches the verify endpoint with
/// the challenge's userId (a label alone proves nothing).
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _RecordingAuthApi extends AuthApi {
  _RecordingAuthApi() : super(Dio());
  final verifyCalls = <(String, String)>[];

  @override
  Future<Authenticated> verifyMfa({required String userId, required String code}) async {
    verifyCalls.add((userId, code));
    return Authenticated(
      user: const AuthUser(id: 'u1', email: 'a@b.test', region: 'US', role: 'USER'),
      accessToken: 'token',
    );
  }
}

Future<void> _pump(WidgetTester t, OtpChannel via, {_RecordingAuthApi? api}) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FixedAuth(AuthAwaitingMfa('u1', via, 'tok-challenge'))),
      if (api != null) authApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const VerifyMfaScreen()),
      ]),
    ),
  ));
  await t.pump();
}

void main() {
  _resendTests();
  testWidgets('via sms — the prompt says the code was texted', (t) async {
    await _pump(t, OtpChannel.sms);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.mfaSubtitleSms), findsOneWidget);
    expect(find.text(l.mfaSubtitleEmail), findsNothing);
  });

  testWidgets('via email — a phoneless user is told to check their INBOX, not their texts', (t) async {
    await _pump(t, OtpChannel.email);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.mfaSubtitleEmail), findsOneWidget,
        reason: 'The code went to the email; pointing at SMS strands the user.');
    expect(find.text(l.mfaSubtitleSms), findsNothing);
  });

  testWidgets('the sixth digit auto-submits to the verify endpoint with the challenge userId', (t) async {
    final api = _RecordingAuthApi();
    await _pump(t, OtpChannel.email, api: api);

    await t.enterText(find.byType(TextField), '123456');
    await t.pump();

    expect(api.verifyCalls, [('u1', '123456')],
        reason: 'The cells must genuinely call POST /auth/login/verify-mfa, '
            'not merely render.');
  });
}

/// The resend control used to be dead: `onPressed: restart` restarted the countdown timer
/// and called no API at all, so a user whose code was lost or expired could only begin the
/// login again — while the button said otherwise. These assert the CALL, because a test
/// that merely found the label would have passed against that dead control.
class _ResendApi extends _RecordingAuthApi {
  final resendCalls = <String>[];
  Object? failWith;

  @override
  Future<void> resendMfa({required String challengeToken}) async {
    resendCalls.add(challengeToken);
    if (failWith != null) throw failWith!;
  }
}


void _resendTests() {
  testWidgets('resend REACHES the endpoint with the challenge token', (t) async {
    final api = _ResendApi();
    await _pump(t, OtpChannel.sms, api: api);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    // Run the 30s countdown out so the control appears.
    await t.pump(const Duration(seconds: 31));
    await t.tap(find.text(l.mfaResend));
    await t.pumpAndSettle();

    expect(api.resendCalls, ['tok-challenge'],
        reason: 'the control must hit POST /auth/login/resend-mfa — it previously only '
            'restarted the countdown timer, which is the bug being fixed');
  });

  testWidgets('a FAILED resend leaves the countdown alone', (t) async {
    // Restarting the timer on failure would tell the user a code is coming when none was
    // sent, and then make them wait 30s before they could try again.
    final api = _ResendApi()..failWith = Exception('network down');
    await _pump(t, OtpChannel.sms, api: api);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.pump(const Duration(seconds: 31));
    await t.tap(find.text(l.mfaResend));
    await t.pumpAndSettle();

    expect(api.resendCalls, hasLength(1));
    // The control is still offered, so the user can try again immediately.
    expect(find.text(l.mfaResend), findsOneWidget,
        reason: 'a failed resend must not start a countdown the user has to sit through');
  });

  testWidgets('a SUCCESSFUL resend restarts the countdown', (t) async {
    final api = _ResendApi();
    await _pump(t, OtpChannel.sms, api: api);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.pump(const Duration(seconds: 31));
    await t.tap(find.text(l.mfaResend));
    await t.pumpAndSettle();

    // Back to counting down: the resend button is gone until it runs out again.
    expect(find.text(l.mfaResend), findsNothing);
  });
}
