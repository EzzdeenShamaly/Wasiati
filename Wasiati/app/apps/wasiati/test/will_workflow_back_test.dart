// Every mid-flow will screen offers a way back OUT of it.
//
// The owner reported the back button missing "everywhere in the workflow of the will".
// The create-will wizard's own Back was a separate bug (see create_will_nav_visible_test);
// this is the other half. The app navigates with go() in 74 places and push() in one, and
// go() REPLACES the stack — so GoRouter has nothing to pop, and any screen relying on
// AppBar's automatic leading renders no back button at all. /wills/new was exactly that:
// `appBar: AppBar()` and nothing else, which looks like a back button in the source and
// is empty chrome on screen.
//
// Browser back is not the answer either. The product ships as an installed PWA, where
// there is no browser chrome, and a step you can only leave by completing it traps
// someone who opened it to look.
//
// So each screen below must carry its OWN back control with an explicit destination.
// Asserted on screen rather than merely in the tree — present-but-below-the-fold is the
// precise failure mode that produced the first report.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/assets/application/assets_providers.dart';
import 'package:wasiati/features/assets/presentation/assets_screen.dart';
import 'package:wasiati/features/commerce/application/entitlement_providers.dart';
import 'package:wasiati/features/legacy/presentation/legacy_messages_screen.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show willsListProvider, willProvider, witnessesProvider, trusteesProvider, willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';
import 'package:wasiati/features/wills/presentation/will_start_screen.dart';
import 'package:wasiati/features/wills/presentation/will_document_screen.dart';
import 'package:wasiati/features/zakat/application/zakat_providers.dart';
import 'package:wasiati/features/zakat/domain/zakat_models.dart';
import 'package:wasiati/features/assets/domain/asset_models.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@wasiati.test', region: 'US', role: 'USER'));
}

class _FakeWillsApi extends WillsApi {
  _FakeWillsApi() : super(Dio());
  @override
  Future<List<Will>> list() async => const [];
  @override
  Future<List<Witness>> witnesses(String willId) async => const [];
  @override
  Future<List<Trustee>> trustees(String willId) async => const [];
}

const _will = Will(
  id: 'w1',
  tier: 'PREMIUM',
  locked: false,
  status: 'SIGNED',
  disclaimerVersion: 'v1',
  shariaShares: [
    ShariaShare(heirRelation: 'WIFE', heirName: 'Layla', sharePercent: 12.5),
    ShariaShare(heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 87.5),
  ],
);

/// Either shape of back control counts: the shared [WasiatiBackLink] used by the
/// in-page breadcrumbs, or an explicit AppBar leading on the screens that have a bar.
/// What is NOT allowed is a bare `AppBar()` trusting an automatic leading that go()
/// navigation never produces.
final _backControl = find.byWidgetPredicate(
  (w) =>
      w is WasiatiBackLink ||
      (w is IconButton && w.icon is Icon && (w.icon as Icon).icon == Icons.arrow_back_ios_new),
  description: 'a back control',
);

/// Tracks where the screen under test navigated to. Every non-test route resolves to
/// this marker, so tapping back both proves the control works and names its destination.
String? _landedAt;

/// A real GoRouter rather than `home:`. Two reasons: the screens call context.go() —
/// WillStartScreen does so from a post-frame callback and throws "No GoRouter found in
/// context" without one — and routing for real is what lets the assertion below check
/// the DESTINATION, not merely that some callback was non-null.
Future<void> _pump(WidgetTester t, String at, Widget screen, List<Override> overrides) async {
  _landedAt = null;
  t.view.physicalSize = const Size(1200, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(path: at, builder: (_, __) => screen),
      for (final other in const ['/wills', '/wills/new', '/wills/new/form', '/wills/:id', '/legacy', '/dashboard'])
        if (other != at)
          GoRoute(
            path: other,
            builder: (_, state) {
              _landedAt = state.matchedLocation;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: overrides,
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

/// The guarantee, in one place: exactly one back control, on screen, that actually
/// lands somewhere when tapped.
Future<void> _expectUsableBack(WidgetTester t, String screen, {required String goesTo}) async {
  expect(_backControl, findsOneWidget, reason: '$screen must render a back control');

  // Measured and tapped on the CHEVRON, not on the outer widget. WasiatiBackLink
  // start-aligns itself inside a stretch Column, so the outer rect spans the whole
  // content width while the button occupies only its left end — t.tap() on that rect
  // aims at the middle and lands on empty page.
  final glyph = find.descendant(of: _backControl, matching: find.byIcon(Icons.arrow_back_ios_new));
  expect(glyph, findsOneWidget, reason: '$screen: back control renders no chevron');

  final r = t.getRect(glyph);
  expect(r.top, greaterThanOrEqualTo(0.0), reason: '$screen: back sits above the viewport');
  expect(r.bottom, lessThanOrEqualTo(900.0),
      reason: '$screen: back sits at ${r.top.toStringAsFixed(0)}-${r.bottom.toStringAsFixed(0)}, below the fold');
  expect(r.width, greaterThan(0.0), reason: '$screen: back has no hit area');

  // Tapped, not invoked directly: a control can be wired and still be unreachable
  // behind an overlay or sized to nothing, and only a real hit test catches that.
  await t.tap(glyph);
  await t.pumpAndSettle();
  expect(_landedAt, goesTo, reason: '$screen: back must land on $goesTo');
}

void main() {
  final auth = authControllerProvider.overrideWith(_FakeAuth.new);

  testWidgets('will start (/wills/new) — the AppBar-only dead end', (t) async {
    await _pump(t, '/wills/new', const WillStartScreen(), [
      auth,
      willsApiProvider.overrideWithValue(_FakeWillsApi()),
      willsListProvider.overrideWith((ref) async => <Will>[]),
      // PREMIUM on purpose: below the aiIntake entitlement the screen is a pure
      // redirect to the form and never renders its chrome at all.
      entitlementProvider.overrideWith(
          (ref) async => <String, dynamic>{'tier': 'PREMIUM', 'active': true, 'features': {'aiIntake': true}}),
    ]);
    await _expectUsableBack(t, '/wills/new', goesTo: '/wills');
  });

  testWidgets('will detail (/wills/:id)', (t) async {
    await _pump(t, '/wills/w1', const WillDetailScreen(willId: 'w1'), [
      auth,
      willProvider('w1').overrideWith((ref) async => _will),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ]);
    await _expectUsableBack(t, '/wills/:id', goesTo: '/wills');
  });

  testWidgets('assets (/wills/:id/assets)', (t) async {
    await _pump(t, '/wills/w1/assets', const AssetsScreen(willId: 'w1'), [
      auth,
      assetsProvider('w1').overrideWith((ref) async => const <EstateAsset>[]),
      // An empty inventory is below nisab; the banner renders its "nothing due" state.
      zakatEstimateProvider.overrideWith((ref) async => const ZakatEstimate(
            currency: 'USD',
            categories: [],
            excludedCryptoMinor: 0,
            unconverted: [],
            zakatableTotalMinor: 0,
            nisabMinor: 650000,
            aboveNisab: false,
            zakatDueMinor: 0,
            hawl: null,
            charityUrl: null,
          )),
    ]);
    await _expectUsableBack(t, '/wills/:id/assets', goesTo: '/wills/w1');
  });

  testWidgets('review & seal (/wills/:id/review)', (t) async {
    await _pump(t, '/wills/w1/review', const ReviewSealScreen(willId: 'w1'), [
      auth,
      willProvider('w1').overrideWith((ref) async => _will),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ]);
    await _expectUsableBack(t, '/wills/:id/review', goesTo: '/wills/w1');
  });

  testWidgets('family messages (/legacy) — in the will flow, absent from the nav rail', (t) async {
    await _pump(t, '/legacy', const LegacyMessagesScreen(), [
      auth,
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{'tier': 'PREMIUM', 'active': true}),
      willsListProvider.overrideWith((ref) async => <Will>[]),
    ]);
    await _expectUsableBack(t, '/legacy', goesTo: '/wills');
  });

  testWidgets('will document (/wills/:id/document) — the document on its own page', (t) async {
    await _pump(t, '/wills/w1/document', const WillDocumentScreen(willId: 'w1'), [
      auth,
      willProvider('w1').overrideWith((ref) async => _will),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ]);
    await _expectUsableBack(t, '/wills/:id/document', goesTo: '/wills/w1');
  });

  testWidgets('a will that FAILS to load still offers a way out', (t) async {
    // The back link on the detail and review screens lives inside the  branch, so
    // for a long time the loading and error states rendered none at all: a transient 500
    // left the owner holding a raw exception and a Try again button.
    await _pump(t, '/wills/w1', const WillDetailScreen(willId: 'w1'), [
      auth,
      willProvider('w1').overrideWith((ref) async => throw Exception('boom')),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ]);
    await _expectUsableBack(t, '/wills/:id (error state)', goesTo: '/wills');
  });

  testWidgets('the review page in its error state offers a way out too', (t) async {
    await _pump(t, '/wills/w1/review', const ReviewSealScreen(willId: 'w1'), [
      auth,
      willProvider('w1').overrideWith((ref) async => throw Exception('boom')),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ]);
    await _expectUsableBack(t, '/wills/:id/review (error state)', goesTo: '/wills/w1');
  });
}
