import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/router/app_router.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/presentation/login_screen.dart';
import 'package:wasiati/features/auth/presentation/splash_screen.dart';
import 'package:wasiati/features/death_claims/presentation/claim_lookup_screen.dart';
import 'package:wasiati/features/death_claims/presentation/claim_submit_screen.dart';
import 'package:wasiati/features/portal/presentation/portal_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// THE ROUTER HAS TWO GATES, AND BOTH KILL THIS FEATURE SILENTLY.
///
/// `/portal` and `/claim/:token` are reached by people with no Wasiati account —
/// a bereaved family member tapping the landing footer link, or the trustee named
/// on someone else's will, following an SMS. Neither gate throws when it is wrong;
/// both just redirect, so the routes look wired up while every real visitor lands
/// on a sign-in form for an account they will never have.
///
///  * GATE 1 — AuthSignedOut: any path not in _authAreaRoutes goes to /login.
///  * GATE 2 — AuthInitial (COLD LOAD): every path went to '/', i.e. splash, which
///    then lands on /login. This is the one that is easy to miss, because a warm
///    in-app navigation never exercises it — only a cold start on a deep link does,
///    which is EXACTLY how every real user arrives here.
///
/// The negative controls matter as much as the positives: they prove the exemption
/// is specific to the accountless surfaces and did not blanket-disable the gates.

/// Holds a fixed AuthState. Overriding build() also suppresses the real
/// controller's bootstrap() microtask, which would otherwise hit the network.
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

/// Pumps the REAL router (not a stand-in route table) at [location], with auth
/// pinned to [auth].
///
/// The navigation happens BEFORE the first pump on purpose. It keeps the test
/// honest — the deep link is the first location the router ever resolves, which is
/// what a cold start on an SMS link actually does — and it avoids building the
/// transient /login frame, whose social-sign-in rows overflow by 5px under the real
/// theme at this width. That overflow is pre-existing and unrelated to this feature
/// (nothing here touches login_screen.dart), but a stray frame of it would fail
/// every assertion below for the wrong reason.
/// The two NEGATIVE controls land on screens this feature does not own, and both
/// misbehave under `pumpAndSettle` for reasons that have nothing to do with routing:
/// SplashScreen holds a CircularProgressIndicator (an animation that never settles),
/// and LoginScreen's social-sign-in rows overflow by 5px under the real theme at this
/// width. Neither is caused by, or fixable from, this change — nothing here touches
/// either file. So those two tests pump a fixed number of frames under the default
/// theme: enough to resolve the redirect, which is the only thing being asserted.
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

const _token = 'aVeryOpaqueClaimTokenAAAAAAAAAAAAAAAAAAAAAA';

void main() {
  group('signed out (gate 1)', () {
    testWidgets('/portal resolves instead of bouncing to /login', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/portal');

      expect(find.byType(PortalScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('/claim resolves', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/claim');

      expect(find.byType(ClaimLookupScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('/claim/:token resolves and carries the token through', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/claim/$_token');

      final screen = t.widget<ClaimSubmitScreen>(find.byType(ClaimSubmitScreen));
      expect(screen.token, _token,
          reason: 'The token is the only credential this screen has; it comes off the path.');
    });

    testWidgets('NEGATIVE CONTROL: a signed-in-only route still bounces to /login', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/dashboard', settle: false);

      expect(find.byType(LoginScreen), findsOneWidget,
          reason: 'The exemption must be specific to the accountless surfaces, not a hole in the gate.');
    });
  });

  group('COLD LOAD, AuthInitial (gate 2 — the one that is easy to miss)', () {
    testWidgets('/portal survives the cold-load redirect', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/portal');

      expect(find.byType(PortalScreen), findsOneWidget,
          reason: 'A family member clicking the landing footer link cold-loads this path. '
              'If AuthInitial sends it to splash, the whole feature is dead on arrival.');
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('/claim/:token survives the cold-load redirect', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/claim/$_token');

      expect(find.byType(ClaimSubmitScreen), findsOneWidget,
          reason: 'The claim link arrives by SMS and is always opened cold.');
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('/claim survives the cold-load redirect', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/claim');

      expect(find.byType(ClaimLookupScreen), findsOneWidget);
    });

    testWidgets('NEGATIVE CONTROL: any other path still goes to splash while booting', (t) async {
      await _pumpRouter(t, const AuthInitial(), '/dashboard', settle: false);

      expect(find.byType(SplashScreen), findsOneWidget,
          reason: 'Exempting the accountless paths must not disable the boot redirect wholesale.');
    });
  });

  group('signed in', () {
    testWidgets('a signed-in user is NOT bounced off /portal', (t) async {
      await _pumpRouter(
        t,
        const AuthSignedIn(AuthUser(id: 'u1', email: 'a@b.com', role: 'USER', region: 'UAE')),
        '/portal',
      );

      expect(find.byType(PortalScreen), findsOneWidget,
          reason: 'A Wasiati customer may legitimately be an heir or trustee on someone '
              "else's will. Bouncing them to their own dashboard locks them out of it.");
    });
  });

  group('the two surfaces reach each other', () {
    testWidgets('the portal actually navigates to the claim flow', (t) async {
      await _pumpRouter(t, const AuthSignedOut(), '/portal');

      final l = await AppLocalizations.delegate.load(const Locale('en'));
      // Presence is not enough — the control must genuinely navigate.
      await t.tap(find.text(l.portalReportDeath));
      await t.pumpAndSettle();

      expect(find.byType(ClaimLookupScreen), findsOneWidget,
          reason: 'The prototype has no "report a death" footer link, so this is the '
              'ONLY entry to the claim flow. If it does not navigate, there is none.');
    });
  });
}
