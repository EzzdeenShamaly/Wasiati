import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/features/auth/presentation/register_screen.dart';
import 'package:wasiati/features/auth/presentation/forgot_password_screen.dart';
import 'package:wasiati/features/auth/presentation/reset_password_screen.dart';
import 'package:wasiati/features/auth/presentation/verify_email_screen.dart';
import 'package:wasiati/features/auth/presentation/verify_mfa_screen.dart';

// Auth screens -> PNGs. Run: flutter test --update-goldens test/_capture_auth.dart
Future<void> _load(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final a in assets) {
    loader.addFont(rootBundle.load(a));
  }
  await loader.load();
}

Future<void> _fonts() async {
  await _load('Fraunces', ['assets/fonts/Fraunces.ttf']);
  await _load('Public Sans', ['assets/fonts/PublicSans.ttf']);
  await _load('Amiri', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']);
  await _load('IBM Plex Sans Arabic',
      ['assets/fonts/IBMPlexSansArabic-Regular.ttf', 'assets/fonts/IBMPlexSansArabic-Bold.ttf']);
  await _load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
}

void _size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

// A GoRouter-backed app so screens that read GoRouterState.of(context) work.
Future<void> _pumpRouted(WidgetTester t, Widget screen, Size size, {bool settle = true}) async {
  await _fonts();
  _size(t, size);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => screen)]),
    ),
  ));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('login', (t) async {
    await _pumpRouted(t, const LoginScreen(), const Size(1000, 1250));
    await expectLater(find.byType(LoginScreen), matchesGoldenFile('cap_login.png'));
  });
  testWidgets('register', (t) async {
    await _pumpRouted(t, const RegisterScreen(), const Size(1000, 1250));
    await expectLater(find.byType(RegisterScreen), matchesGoldenFile('cap_register.png'));
  });
  testWidgets('forgot', (t) async {
    await _pumpRouted(t, const ForgotPasswordScreen(), const Size(1000, 1100));
    await expectLater(find.byType(ForgotPasswordScreen), matchesGoldenFile('cap_forgot.png'));
  });
  testWidgets('reset', (t) async {
    await _pumpRouted(t, const ResetPasswordScreen(), const Size(1000, 1100));
    await expectLater(find.byType(ResetPasswordScreen), matchesGoldenFile('cap_reset.png'));
  });
  testWidgets('verify_email', (t) async {
    await _pumpRouted(t, const VerifyEmailScreen(), const Size(1000, 1100), settle: false);
    await expectLater(find.byType(VerifyEmailScreen), matchesGoldenFile('cap_verify_email.png'));
  });
  testWidgets('mfa', (t) async {
    await _pumpRouted(t, const VerifyMfaScreen(), const Size(1000, 1100), settle: false);
    await expectLater(find.byType(VerifyMfaScreen), matchesGoldenFile('cap_mfa.png'));
  });
}
