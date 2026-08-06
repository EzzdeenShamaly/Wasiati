// Back / Continue are reachable on every create-will step, at any window height.
//
// The owner reported the Back button "disappearing on most will form pages". It was never
// missing from the tree — it was the LAST child of a page-length SingleChildScrollView, so
// its bottom edge sat a fixed ~984px down the page on every step. A browser maximised on a
// 1080p monitor has roughly 950-985px of viewport once its chrome is taken, so the controls
// landed just below the fold — and Flutter's scrollbar thumb was not persistent, so nothing
// indicated the page continued. That margin of a few dozen pixels is why it struck "most"
// steps rather than all, and why it looked erratic.
//
// The wizard is five steps, not six: Review & seal is its own page now (DECISIONS §0), so
// the loops below stop at 5. Left at 6 they would not fail — _next() clamps — they would
// silently re-measure step 5 and report a green sixth step that does not exist.
//
// The row is now pinned below the scroll. These tests assert the guarantee the owner cares
// about — the control is ON SCREEN — rather than merely present in the widget tree, which is
// what a findsOneWidget check would have (wrongly) confirmed all along.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';

class _Api extends WillsApi {
  final int at;
  _Api(this.at) : super(Dio());
  Will get _d => Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': at,
        'sex': 'male',
        'wives': 1,
        'sons': 3,
        'daughters': 2,
        'mother': true,
        'father': true,
        'madhhab': 'JUMHUR',
        'bequest': {'name': 'Orphans fund', 'third': 40.0},
        'wishes': {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
        'words': '',
      });
  @override
  Future<List<Will>> list() async => [_d];
  @override
  Future<Will> getOne(String id) async => _d;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _d;
  @override
  Future<Will> updateDraft(String w, Map<String, dynamic> s) async => _d;
  @override
  Future<List<HeirContact>> heirContacts(String w) async => const [];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

Future<void> _open(WidgetTester t, {required int step, required Size size}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(_Api(step)),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Keyed per step ON PURPOSE. pumpWidget UPDATES an existing element tree rather than
      // rebuilding it when the root type is unchanged, so without a distinct key the
      // screen's State survives between loop iterations, _restore never re-runs, and every
      // "step" silently re-measures step 1 — a green test covering one sixth of the claim.
      home: KeyedSubtree(key: ValueKey('step-$step'), child: const CreateWillScreen()),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  // 950x... is the case that bit: a maximised browser on a 1080p monitor. The others bracket
  // it so the guarantee is not accidentally true only at one size.
  const sizes = <Size>[
    Size(1920, 960), // maximised 1080p, browser chrome taken — the owner's case
    Size(1512, 860), // laptop
    Size(1440, 780), // short window
    Size(1280, 700), // very short
    Size(1920, 1080), // tall
  ];

  for (final size in sizes) {
    testWidgets('Back is on screen at every step @ ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      for (var step = 1; step <= 5; step++) {
        await _open(t, step: step, size: size);

        final back = find.widgetWithText(OutlinedButton, 'Back');
        expect(back, findsOneWidget, reason: 'step $step must render a Back control');

        // The point of the whole fix: present in the tree is not enough, it must be VISIBLE
        // without scrolling.
        final r = t.getRect(back.first);
        expect(r.bottom, lessThanOrEqualTo(size.height),
            reason: 'step $step @ ${size.height.toInt()}px: Back sits at ${r.top.toStringAsFixed(0)}'
                '-${r.bottom.toStringAsFixed(0)}, below the fold');
        expect(r.top, greaterThanOrEqualTo(0.0), reason: 'step $step: Back is above the viewport');
      }
    });
  }

  testWidgets('the forward control is on screen too, on every step', (t) async {
    // It vanished with Back — the owner confirmed both went — so it is held to the same bar.
    // Scoped to the pinned bar: the review step also renders FilledButtons inside the
    // scroll (the Premium video upsell), and an unscoped .last finds one of those.
    const size = Size(1920, 960);
    for (var step = 1; step <= 5; step++) {
      await _open(t, step: step, size: size);
      // byWidgetPredicate, not byType: the review step's seal control is FilledButton.icon,
      // whose widget is a private SUBCLASS of FilledButton, and byType demands an exact
      // runtime-type match — so byType(FilledButton) silently finds nothing on step 6.
      final fwd = find.descendant(
        of: find.byKey(const ValueKey('createWillNav')),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(fwd, findsOneWidget, reason: 'step $step must render exactly one forward control in the nav');
      final r = t.getRect(fwd);
      expect(r.bottom, lessThanOrEqualTo(size.height), reason: 'step $step: forward control below the fold');
    }
  });

  testWidgets('Back still navigates — pinning it did not orphan the handler', (t) async {
    await _open(t, step: 3, size: const Size(1512, 900));
    expect(find.textContaining('Step 3'), findsWidgets);

    // Invoke the handler the pinned button actually carries, rather than synthesising a
    // tap. The risk this test exists for is that moving the row out of the step bodies
    // left a button wired to nothing; that is exactly what onPressed proves. Driving it
    // this way also keeps the assertion off the stubbed autosave, which re-serves step 3.
    final back = t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'));
    expect(back.onPressed, isNotNull, reason: 'the pinned Back must still be wired');
    back.onPressed!();
    await t.pump();
    expect(find.textContaining('Step 2'), findsWidgets, reason: 'Back must move the wizard back a step');
  });
}
