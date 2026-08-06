import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/router/app_router.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/features/auth/presentation/splash_screen.dart';
import 'package:wasiati/features/confirm/presentation/trustee_confirm_screen.dart';
import 'package:wasiati/features/confirm/presentation/witness_sign_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// /trustee/:id and /witness/:id are reached from an SMS by someone with NO
/// Wasiati account, so — like /portal and /claim (see
/// portal_claim_routing_test.dart, whose harness this reuses) — they must
/// survive BOTH router gates:
///
///  * GATE 1 — AuthSignedOut: any path not in the allow-list goes to /login.
///  * GATE 2 — AuthInitial (COLD LOAD): every path goes to splash → /login.
///    A warm in-app navigation never exercises this branch; the SMS link, the
///    ONLY way a real trustee or witness arrives, always does.
///
/// Neither gate throws when it is wrong; both just redirect — the routes look
/// wired while every real trustee lands on a sign-in form for an account they
/// do not have, no trustee ever reaches CONFIRMED, and the release gate can
/// never be satisfied. These tests are what keeps that failure loud.
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

Future<void> _pumpRouter(
  WidgetTester t,
  AuthState auth,
  String location, {
  bool settle = true,
}) async {
  t.view.physicalSize = const Size(1100, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final container = ProviderContainer(
    overrides: [authControllerProvider.overrideWith(() => _FixedAuth(auth))],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  // Navigating BEFORE the first pump mirrors a cold start on a deep link — the
  // SMS path is the first location the router ever resolves.
  router.go(location);

  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: settle ? WasiatiTheme.light() : ThemeData(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _id = 'trs_0123456789abcdef';

void main() {
  group('signed out (gate 1)', () {
    testWidgets('/trustee/:id resolves instead of bouncing to /login', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/trustee/$_id');

      final screen = t.widget<TrusteeConfirmScreen>(find.byType(TrusteeConfirmScreen));
      expect(screen.trusteeId, _id, reason: 'The roster id comes off the path.');
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('/witness/:id resolves instead of bouncing to /login', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/witness/$_id');

      final screen = t.widget<WitnessSignScreen>(find.byType(WitnessSignScreen));
      expect(screen.witnessId, _id);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('COLD LOAD, AuthInitial (gate 2 — the one that is easy to miss)', () {
    testWidgets('/trustee/:id survives the cold-load redirect', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/trustee/$_id');

      expect(find.byType(TrusteeConfirmScreen), findsOneWidget,
          reason: 'The trustee link arrives by SMS and is ALWAYS opened cold. '
              'If AuthInitial sends it to splash, no trustee can ever confirm.');
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('/witness/:id survives the cold-load redirect', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/witness/$_id');

      expect(find.byType(WitnessSignScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('NEGATIVE CONTROL: a bare /trustee (no id) still redirects', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/trustee', settle: false);

      expect(find.byType(TrusteeConfirmScreen), findsNothing,
          reason: 'Only the id-carrying SMS path is public; the exemption must not '
              'blanket-open a /trustee prefix with no screen behind it.');
    });
  });

  group('the flow actually advances', () {
    testWidgets('trustee: Accept the role is present and Decline reaches the declined state',
        (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/trustee/$_id');
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.tcAcceptBtn), findsOneWidget);

      // Decline is pure client state — no network — so it can be driven here.
      // (Accept hits the real send-code endpoint; that path is covered by the
      // integration test in witnesses_trustees_integration_test.dart.)
      await t.tap(find.text(l.tcDecline));
      await t.pumpAndSettle();
      expect(find.text(l.confirmDeclinedTitle), findsOneWidget);
    });

    testWidgets('witness: the sign button stays disabled until a legal name is typed', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/witness/$_id');
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      final button = find.widgetWithText(FilledButton, l.wcSignBtn);
      expect(t.widget<FilledButton>(button).onPressed, isNull,
          reason: 'Without a legal name the backend would refuse the signature anyway; '
              'the button must not pretend otherwise.');

      await t.enterText(find.byType(TextField).first, 'Waleed Witness');
      await t.pump();
      expect(t.widget<FilledButton>(button).onPressed, isNotNull);
    });
  });
}
