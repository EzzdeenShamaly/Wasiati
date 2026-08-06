import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/passkey_service.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/passkey_exceptions.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The login screen's passkey button was a `_soon` stub — the classic house
/// disease: backend complete, suite green, feature nonexistent. These tests pin
/// the cure at the button: tapping it must drive AuthController.loginWithPasskey
/// through PasskeyService and, on success, actually produce a signed-in session.
/// (The browser prompt itself can't run on the VM — the ceremony seam is faked;
/// everything on both sides of it is real.)

class _FakePasskeyService extends PasskeyService {
  _FakePasskeyService({this.error}) : super(AuthApi(Dio()), supported: true);
  final Object? error;
  int signIns = 0;

  @override
  Future<Authenticated> signIn() async {
    signIns++;
    if (error != null) throw error!;
    return Authenticated(
      user: const AuthUser(id: 'u1', email: 'a@b.test', region: 'QA', role: 'USER'),
      accessToken: 'jwt-passkey',
    );
  }
}

Future<void> _pump(WidgetTester t, {List<Override> overrides = const []}) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(initialLocation: '/', routes: [
        GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
      ]),
    ),
  ));
  await t.pumpAndSettle();
}

/// Lets the snackbar's auto-dismiss timer expire so the test ends timer-clean.
Future<void> _drainSnackbar(WidgetTester t) async {
  await t.pump(const Duration(seconds: 5));
  await t.pumpAndSettle();
}

void main() {
  // A successful passkey sign-in records "this device has one" locally. Without the mock
  // store the plugin channel never answers and that write hangs, so pumpAndSettle stalls.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the passkey button signs the user in when the ceremony succeeds', (t) async {
    final service = _FakePasskeyService();
    await _pump(t, overrides: [passkeyServiceProvider.overrideWithValue(service)]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.authUsePasskey));
    await t.pumpAndSettle();

    expect(service.signIns, 1, reason: 'the button must run the real ceremony chain, not a stub');
    final container = ProviderScope.containerOf(t.element(find.byType(LoginScreen)), listen: false);
    expect(container.read(authControllerProvider), isA<AuthSignedIn>(),
        reason: 'a successful ceremony must END SIGNED IN — reaching the endpoint is not enough');
  });

  testWidgets('a passkey login never detours through the OTP screen (AuthAwaitingMfa)', (t) async {
    final service = _FakePasskeyService();
    await _pump(t, overrides: [passkeyServiceProvider.overrideWithValue(service)]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    final container = ProviderScope.containerOf(t.element(find.byType(LoginScreen)), listen: false);
    final seen = <AuthState>[];
    container.listen<AuthState>(authControllerProvider, (_, s) => seen.add(s));

    await t.tap(find.text(l.authUsePasskey));
    await t.pumpAndSettle();

    expect(seen.whereType<AuthAwaitingMfa>(), isEmpty,
        reason: 'f242634: the passkey is the one login path exempt from the always-OTP rule');
  });

  testWidgets('user cancels (or has no passkey here): a clear message, not a silent no-op', (t) async {
    final service = _FakePasskeyService(error: const PasskeyCancelled());
    await _pump(t, overrides: [passkeyServiceProvider.overrideWithValue(service)]);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.authUsePasskey));
    await t.pumpAndSettle();

    expect(find.text(l.passkeyErrorCancelled), findsOneWidget);
    final container = ProviderScope.containerOf(t.element(find.byType(LoginScreen)), listen: false);
    expect(container.read(authControllerProvider), isNot(isA<AuthSignedIn>()));
    await _drainSnackbar(t);
  });

  testWidgets('browser without WebAuthn (the VM stub is exactly that): the unsupported message', (t) async {
    // No service override: the conditional import resolves to the stub here, so
    // this exercises the REAL default wiring end to end.
    await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.authUsePasskey));
    await t.pumpAndSettle();

    expect(find.text(l.passkeyErrorUnsupported), findsOneWidget);
    expect(find.text(l.authMethodSoon), findsNothing,
        reason: 'the "not enabled in this build yet" stub must be gone from the passkey path');
    await _drainSnackbar(t);
  });
}
