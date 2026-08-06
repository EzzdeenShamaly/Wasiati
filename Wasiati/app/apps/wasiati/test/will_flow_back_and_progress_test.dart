// Back goes to the PREVIOUS STEP, and the progress bar tells the truth.
//
// Two owner reports, one root cause each.
//
// BACK: the app navigates with go(), which REPLACES the stack, so every back control was
// written as another go() to a hard-coded destination — a guess about where you came from.
// The guess was wrong exactly where it mattered. Leaving the wizard for the review page
// threw the owner out to the will dashboard instead of back to step 5, and "Edit assets &
// loans" on step 4 — the app's one real push() — came back to the dashboard too, abandoning
// the half-filled form. The wizard now PUSHES the review page and every back control pops
// when there is something to pop (BackNav.goBack).
//
// PROGRESS BAR: the wizard drew six segments and the review page drew none, so the bar
// reached five of six and then vanished on the screen that completes the flow.

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
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider, willProvider, witnessesProvider, trusteesProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';
import 'package:wasiati/features/wills/presentation/widgets/will_step_bar.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@wasiati.test', region: 'US', role: 'USER'));
}

class _Api extends WillsApi {
  _Api(this.at) : super(Dio());
  final int at;
  final List<int> stepsWritten = [];

  Will get _d => Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': at,
        'sex': 'male',
        'wives': 1,
        'sons': 2,
        'madhhab': 'JUMHUR',
        'wishes': const {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
        'words': 'Some words.',
      });
  @override
  Future<List<Will>> list() async => [_d];
  @override
  Future<Will> getOne(String id) async => _d;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _d;
  @override
  Future<Will> updateDraft(String w, Map<String, dynamic> s) async {
    stepsWritten.add(s['step'] as int);
    return _d;
  }

  @override
  Future<List<HeirContact>> heirContacts(String w) async => const [];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

/// The real route table for the two screens under test, so push/pop behaves as it does in
/// the app. `/wills` is the escape hatch the old code jumped to; landing there is a FAILURE
/// in these tests, which is why it is recorded rather than merely rendered.
String? landedOutside;

Future<_Api> _open(WidgetTester t, {required int step}) async {
  landedOutside = null;
  final api = _Api(step);
  t.view.physicalSize = const Size(1400, 1100);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/wills/new/form',
    routes: [
      GoRoute(path: '/wills/new/form', builder: (_, __) => const CreateWillScreen()),
      GoRoute(
        path: '/wills/:id/review',
        builder: (_, s) => ReviewSealScreen(willId: s.pathParameters['id']!),
      ),
      for (final p in const ['/wills', '/wills/:id', '/dashboard'])
        GoRoute(
          path: p,
          builder: (_, s) {
            landedOutside = s.matchedLocation;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsApiProvider.overrideWithValue(api),
      willProvider('d1').overrideWith((ref) async => api._d),
      witnessesProvider('d1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('d1').overrideWith((ref) async => const <Trustee>[]),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

/// How many segments of the bar are filled. Reads the rendered decoration rather than any
/// step field, because the bar being *drawn* correctly is the whole claim.
int _filledSegments(WidgetTester t) {
  final bar = find.byType(WillStepBar);
  expect(bar, findsOneWidget, reason: 'the flow must show a progress bar');
  return t
      .widgetList<Container>(find.descendant(of: bar, matching: find.byType(Container)))
      .where((c) => (c.decoration as BoxDecoration?)?.color == WasiatiColors.brassGold)
      .length;
}

void main() {
  group('back goes to the previous step', () {
    testWidgets('review -> back lands on step 5, not the will dashboard', (t) async {
      await _open(t, step: 5);
      expect(find.textContaining('Step 5 of 6'), findsWidgets);

      // Forward into review.
      await t.tap(find.text('Continue to review'));
      await t.pumpAndSettle();
      expect(find.byType(ReviewSealScreen), findsOneWidget, reason: 'should be on the review page');

      // Back out of it.
      await t.tap(find.descendant(
        of: find.byType(WasiatiBackLink),
        matching: find.byIcon(Icons.arrow_back_ios_new),
      ));
      await t.pumpAndSettle();

      expect(landedOutside, isNull,
          reason: 'back from review must not leave the flow — it landed on $landedOutside');
      expect(find.byType(CreateWillScreen), findsOneWidget);
      expect(find.textContaining('Step 5 of 6'), findsWidgets,
          reason: 'back from review belongs on the step it was reached from');
    });

    testWidgets('the wizard is still on step 5 with its answers intact', (t) async {
      // Popping must return to the LIVE wizard, not a fresh one restored from the server —
      // otherwise "back" silently discards anything typed since the last autosave.
      final api = await _open(t, step: 5);
      await t.tap(find.text('Continue to review'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(
        of: find.byType(WasiatiBackLink),
        matching: find.byIcon(Icons.arrow_back_ios_new),
      ));
      await t.pumpAndSettle();

      expect(find.text('Some words.'), findsWidgets, reason: 'the words step keeps what was written');
      // Handing off wrote step 6; coming back must correct that, or resuming later would
      // drop the owner on review when they had deliberately stepped back.
      expect(api.stepsWritten, contains(6));
      expect(api.stepsWritten.last, 5, reason: 'the draft must record where the owner actually is');
    });

    testWidgets('step 1 back still leaves the flow — there is no earlier step', (t) async {
      await _open(t, step: 1);
      await t.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await t.pumpAndSettle();
      expect(landedOutside, '/wills');
    });
  });

  group('the progress bar is accurate', () {
    testWidgets('each guided step fills exactly that many of six', (t) async {
      for (var step = 1; step <= 5; step++) {
        await _open(t, step: step);
        expect(_filledSegments(t), step,
            reason: 'step $step should fill $step of $kWillFlowSteps segments');
      }
    });

    testWidgets('the review page shows the bar, complete', (t) async {
      // It used to render no bar at all, so the flow appeared to stall at five of six.
      await _open(t, step: 5);
      await t.tap(find.text('Continue to review'));
      await t.pumpAndSettle();

      expect(find.byType(ReviewSealScreen), findsOneWidget);
      expect(_filledSegments(t), kWillFlowSteps,
          reason: 'the last step of the flow must show the bar complete');
    });
  });
}
