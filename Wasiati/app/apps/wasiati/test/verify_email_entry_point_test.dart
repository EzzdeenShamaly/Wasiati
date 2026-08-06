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
import 'package:wasiati/features/auth/presentation/verify_email_screen.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// Sealing requires a confirmed email (fdb4c3e), but /verify-email's resend
/// form was orphaned — registered, reachable by emailed link, and navigated to
/// by NOTHING in the app. An unverified owner reaching the seal step got the
/// backend's 400 and a dead end on the critical path. Following
/// entry_points_reachable_test.dart: the notice must genuinely NAVIGATE, and
/// the resend must genuinely CALL its endpoint — presence proves nothing.
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _RecordingAuthApi extends AuthApi {
  _RecordingAuthApi() : super(Dio());
  final resent = <String>[];

  @override
  Future<void> resendVerification(String email) async => resent.add(email);
}

const _draft = Will(id: 'w1', tier: 'STANDARD', locked: false, status: 'DRAFT');

Future<_RecordingAuthApi> _pump(WidgetTester t, {required bool emailVerified}) async {
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _RecordingAuthApi();
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FixedAuth(const AuthSignedIn(
          AuthUser(id: 'u1', email: 'owner@wasiati.test', role: 'USER', region: 'US')))),
      authApiProvider.overrideWithValue(api),
      emailVerifiedProvider.overrideWith((ref) async => emailVerified),
      willProvider.overrideWith((ref, id) async => _draft),
      willsListProvider.overrideWith((ref) async => const [_draft]),
      witnessesProvider.overrideWith((ref, id) async => const <Witness>[]),
      trusteesProvider.overrideWith((ref, id) async => const <Trustee>[]),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(initialLocation: '/wills/w1/review', routes: [
        GoRoute(
            path: '/wills/:id/review',
            builder: (_, s) => ReviewSealScreen(willId: s.pathParameters['id']!)),
        GoRoute(path: '/verify-email', builder: (_, __) => const VerifyEmailScreen()),
      ]),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('unverified owner: the seal step offers the fix and it lands on /verify-email',
      (t) async {
    await _pump(t, emailVerified: false);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.text(l.rsVerifyEmailNotice), findsOneWidget,
        reason: 'Sealing will be refused for this owner; the step must say why '
            'BEFORE the backend 400 does.');

    await t.ensureVisible(find.text(l.rsVerifyEmailCta));
    await t.tap(find.text(l.rsVerifyEmailCta));
    await t.pumpAndSettle();
    expect(find.byType(VerifyEmailScreen), findsOneWidget,
        reason: 'The CTA must genuinely navigate — /verify-email was registered '
            'yet nothing in the app ever went there.');
  });

  testWidgets('...and the resend there actually asks the backend for another mail', (t) async {
    final api = await _pump(t, emailVerified: false);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.ensureVisible(find.text(l.rsVerifyEmailCta));
    await t.tap(find.text(l.rsVerifyEmailCta));
    await t.pumpAndSettle();

    await t.tap(find.text(l.verifyEmailResend));
    await t.pumpAndSettle();
    expect(api.resent, ['owner@wasiati.test'],
        reason: 'Signed in, the resend must hit /auth/resend-verification with '
            'the session\'s address — this is the recovery for a user who never '
            'got the sign-up mail.');
  });

  testWidgets('verified owner: no banner', (t) async {
    await _pump(t, emailVerified: true);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.rsVerifyEmailNotice), findsNothing);
  });
}
