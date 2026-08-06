// The guided wizard ends at step 5 and hands off to the Review & seal page.
//
// DECISIONS §0 (owner, 11 July 2026): "guided steps -> a required Review page -> seal".
// It was not built that way. Review was a sixth step INSIDE the wizard that also sealed,
// which had two consequences: the dedicated Review & Seal page was unreachable from the
// create flow (you only got there from an existing will), and step 6 put the same shares
// table on screen twice — once as the review card, once as the live-fara'id panel beside
// it, same heirs, same basis text, same percentages.
//
// So the two things worth pinning are that the wizard LEAVES for the review page, and
// that it can no longer seal on its own.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';

/// Records the calls that must NOT happen from the wizard any more.
class _Api extends WillsApi {
  final int at;
  _Api(this.at) : super(Dio());
  final List<String> calls = [];

  Will get _d => Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': at,
        'sex': 'male',
        'wives': 1,
        'sons': 2,
        'daughters': 1,
        'mother': true,
        'madhhab': 'JUMHUR',
        'wishes': {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
        'words': 'Some words already written.',
      });
  @override
  Future<List<Will>> list() async => [_d];
  @override
  Future<Will> getOne(String id) async => _d;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _d;
  @override
  Future<Will> updateDraft(String w, Map<String, dynamic> s) async {
    calls.add('updateDraft:${s['step']}');
    return _d;
  }

  @override
  Future<Will> sign(String id, {String? signatureData}) async {
    calls.add('sign');
    return _d;
  }

  @override
  Future<Will> seal(String id) async {
    calls.add('seal');
    return _d;
  }

  @override
  Future<List<HeirContact>> heirContacts(String w) async => const [];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

String? landedAt;

Future<_Api> _open(WidgetTester t, {required int step}) async {
  landedAt = null;
  final api = _Api(step);
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/wills/new/form',
    routes: [
      GoRoute(path: '/wills/new/form', builder: (_, __) => const CreateWillScreen()),
      for (final p in const ['/wills', '/wills/:id/review', '/wills/:id/sealed', '/wills/:id'])
        GoRoute(
          path: p,
          builder: (_, s) {
            landedAt = s.matchedLocation;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
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

void main() {
  testWidgets('step 5 is the last one in the wizard, and forward goes to review', (t) async {
    final api = await _open(t, step: 5);
    expect(find.textContaining('Step 5 of 6'), findsWidgets, reason: 'the draft should open on step 5');

    final fwd = find.descendant(
      of: find.byKey(const ValueKey('createWillNav')),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(fwd, findsOneWidget);
    // Named for where it goes. "Continue" would imply another step in the same screen.
    expect(find.text('Continue to review'), findsOneWidget);

    await t.tap(fwd);
    await t.pumpAndSettle();

    expect(landedAt, '/wills/d1/review', reason: 'the last guided step must hand off to the review page');
    // Flushed on the way out, marked as step 6 — the review page reads the will from the
    // server, so anything still in the 0.6s autosave debounce would not be in it.
    expect(api.calls, contains('updateDraft:6'));
    expect(api.calls, isNot(contains('sign')), reason: 'the wizard must not sign');
    expect(api.calls, isNot(contains('seal')), reason: 'the wizard must not seal');
  });

  testWidgets('there is no sixth step to walk into', (t) async {
    await _open(t, step: 5);
    // Forward from 5 leaves the screen entirely, so no "Step 6 of 6" is ever rendered
    // by the wizard — that label belongs to the review page.
    expect(find.textContaining('Step 6 of 6'), findsNothing);
  });

  testWidgets('a draft saved on step 6 opens on step 5, editable', (t) async {
    // This used to assert the opposite — that such a draft redirects to the review page,
    // on the reasoning that a draft should reopen where it was left. That trapped people.
    // Handing off to review is what writes step 6, so EVERY returning draft matched, and
    // the redirect used go(): review had nothing to pop, its back fell through to the will
    // detail, and the detail page's only forward action is review again. Steps 1-5 became
    // unreachable and the will could not be edited at all.
    //
    // Reopening exactly where you left off is worth less than being able to change your
    // will. Review is one Continue away from step 5.
    await _open(t, step: 6);
    expect(landedAt, isNull, reason: 'opening a draft must not redirect — it went to ');
    expect(find.textContaining('Step 5 of 6'), findsWidgets);
  });
}
