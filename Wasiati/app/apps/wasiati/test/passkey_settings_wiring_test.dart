import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/application/passkey_service.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/passkey_exceptions.dart';
import 'package:wasiati/features/checkin/application/checkin_providers.dart';
import 'package:wasiati/features/checkin/data/checkin_api.dart';
import 'package:wasiati/features/settings/presentation/settings_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// Registration is what makes passkey sign-in EXIST: without a row that creates
/// a credential, the login button is decoration (no user can ever have one).
/// So these tests pin the supply side — the Settings row must genuinely run
/// PasskeyService.register(), voice success, and voice a cancelled prompt.

class _FixedAuth extends AuthController {
  @override
  AuthState build() =>
      const AuthSignedIn(AuthUser(id: 'u1', email: 'a@b.test', region: 'QA', role: 'USER'));
}

class _FakePasskeyService extends PasskeyService {
  _FakePasskeyService({this.error}) : super(AuthApi(Dio()), supported: true);
  final Object? error;
  int registrations = 0;

  @override
  Future<void> register() async {
    registrations++;
    if (error != null) throw error!;
  }
}

Future<void> _pump(WidgetTester t, _FakePasskeyService service) async {
  t.view.physicalSize = const Size(1000, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FixedAuth.new),
      passkeyServiceProvider.overrideWithValue(service),
      checkinStatusProvider.overrideWith((ref) async => const CheckinStatus(
          enabled: false,
          frequency: 'QUARTERLY',
          lastConfirmedAt: null,
          remindersSent: 0,
          trusteeAlerted: false,
          claimInitPolicy: 'BOTH')),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettingsScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _tapAddPasskey(WidgetTester t, AppLocalizations l) async {
  await t.ensureVisible(find.text(l.settingsAddPasskey));
  await t.pumpAndSettle();
  await t.tap(find.text(l.settingsAddPasskey));
  await t.pumpAndSettle();
}

/// Lets the snackbar's auto-dismiss timer expire so the test ends timer-clean.
Future<void> _drainSnackbar(WidgetTester t) async {
  await t.pump(const Duration(seconds: 5));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Security has an "Add a passkey" row that actually runs the registration ceremony', (t) async {
    final service = _FakePasskeyService();
    await _pump(t, service);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _tapAddPasskey(t, l);

    expect(service.registrations, 1,
        reason: 'presence is not enough — the row must reach /auth/passkeys/register/* via the service');
    expect(find.text(l.passkeyAdded), findsOneWidget,
        reason: 'success must be voiced: the user needs to know sign-in now works here');
    await _drainSnackbar(t);
  });

  testWidgets('a cancelled registration prompt is voiced, never a silent no-op', (t) async {
    final service = _FakePasskeyService(error: const PasskeyCancelled());
    await _pump(t, service);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _tapAddPasskey(t, l);

    expect(service.registrations, 1);
    expect(find.text(l.passkeyErrorRegisterCancelled), findsOneWidget);
    expect(find.text(l.passkeyAdded), findsNothing);
    await _drainSnackbar(t);
  });

  testWidgets('a device that already holds a passkey for the account is told exactly that', (t) async {
    final service = _FakePasskeyService(error: const PasskeyAlreadyRegistered());
    await _pump(t, service);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _tapAddPasskey(t, l);

    expect(find.text(l.passkeyErrorAlreadyRegistered), findsOneWidget);
    await _drainSnackbar(t);
  });
}
