// "Words for my family" (create-will step 5) arrives PRE-FILLED with the classic wasiyya.
//
// The owner reported the preloaded text gone, and the will review screen and the exported
// PDF "a disaster" with it. Those are one defect, not three: the template had become a
// faded hint that only materialised if you pressed Enter on the empty field. Nobody does
// that, so the field stayed empty — and both the review step's quote block and the PDF's
// "Words for my family" section are gated on the message being non-empty, so both silently
// vanished from every will made after the change.
//
// wasiyya_template_test.dart already pins the FORMATTER (Enter seeds, Delete clears). It
// stayed green throughout, because the formatter was never broken — what broke was that
// nothing put the template in the field in the first place. That is the gap these tests
// close: they drive the real screen and assert on what the owner actually sees.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider, willProvider, witnessesProvider, trusteesProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';

/// Opens the flow on a restored draft at [openAtStep] with an empty words field —
/// the state a returning owner is in, and the one the regression left blank.
class _FakeWillsApi extends WillsApi {
  final int openAtStep;
  _FakeWillsApi({required this.openAtStep}) : super(Dio());

  Will get _draft => Will(
        id: 'draft-1',
        tier: 'STANDARD',
        locked: false,
        status: 'DRAFT',
        draftState: {
          'step': openAtStep,
          'sex': 'male',
          'sons': 2,
          'daughters': 1,
          'madhhab': 'JUMHUR',
          'wishes': {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
          'words': '',
        },
      );

  @override
  Future<List<Will>> list() async => [_draft];
  @override
  Future<Will> getOne(String id) async => _draft;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async =>
      _draft;
  @override
  Future<Will> updateDraft(String willId, Map<String, dynamic> draftState) async => _draft;
  @override
  Future<List<HeirContact>> heirContacts(String willId) async => const [];
  @override
  Future<List<Witness>> witnesses(String willId) async => const [];
  @override
  Future<List<Trustee>> trustees(String willId) async => const [];
}

Future<void> _open(WidgetTester t, {required int atStep}) async {
  t.view.physicalSize = const Size(1200, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(_FakeWillsApi(openAtStep: atStep)),
      disclaimerProvider.overrideWith(
        (ref) async => (version: 'v1', text: 'This is a religious tool, not legal advice.'),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const CreateWillScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

/// The words field is the only multi-line TextField on step 5.
String _wordsText(WidgetTester t) {
  final fields = t.widgetList<TextField>(find.byType(TextField)).where((f) => (f.maxLines ?? 1) > 1);
  expect(fields, isNotEmpty, reason: 'step 5 should render the multi-line words field');
  return fields.first.controller?.text ?? '';
}

void main() {
  // The opening line of cwWordsDefault. Asserting on a fragment rather than the whole
  // 700-character template keeps the test from churning every time the copy is reworded,
  // while still failing loudly if the field is empty or holds something else.
  const opening = 'In the name of Allah';

  testWidgets('walking onto step 5 arrives with the wasiyya already in the field', (t) async {
    await _open(t, atStep: 4); // estate & bequest — one Continue short of words
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();

    expect(_wordsText(t), contains(opening),
        reason: 'the template must be real editable text on arrival, not a hint');
  });

  testWidgets('resuming a draft straight onto step 5 is seeded too', (t) async {
    // Resuming restores _step directly and never passes through _next(), so this is a
    // separate path — and the one a returning owner actually takes.
    await _open(t, atStep: 5);
    expect(_wordsText(t), contains(opening));
  });

  testWidgets('the seeded text is editable — it is the owner\'s to change', (t) async {
    await _open(t, atStep: 5);
    final seeded = _wordsText(t);
    // Appending passes straight through the formatter: from here the words are theirs.
    await t.enterText(find.byType(TextField).first, '$seeded\n\nAnd forgive me.');
    await t.pumpAndSettle();
    expect(_wordsText(t), endsWith('And forgive me.'));
    expect(_wordsText(t), contains(opening), reason: 'appending must not drop the template');
  });

  testWidgets('deleting the untouched template clears the field and it stays cleared', (t) async {
    await _open(t, atStep: 5);
    final seeded = _wordsText(t);
    // Any deletion off the PRISTINE template wipes it (WasiyyaTemplateFormatter) so the
    // owner can start from a blank page. Seeding must not immediately refill it.
    await t.enterText(find.byType(TextField).first, seeded.substring(0, seeded.length - 1));
    await t.pumpAndSettle();
    expect(_wordsText(t), isEmpty);
  });

  testWidgets('words the owner already wrote are never overwritten by the template', (t) async {
    await _open(t, atStep: 4);
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '${_wordsText(t)} Mine.');
    await t.pumpAndSettle();

    // Step back out and in again: seeding only ever fills an EMPTY field.
    await t.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();
    expect(_wordsText(t), endsWith(' Mine.'));
  });

  testWidgets('the review page quotes the words back — the block that vanished', (t) async {
    // Asserted on the Review & seal PAGE, not by walking the wizard into a sixth step:
    // sealing moved there (DECISIONS §0), so that is where the words have to be read back
    // before the irreversible button. The will carries the seeded opening as its saved
    // personalMessage, which is what the wizard flushes on the way out.
    t.view.physicalSize = const Size(1200, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    const w = Will(
      id: 'draft-1',
      tier: 'STANDARD',
      locked: false,
      status: 'DRAFT',
      personalMessage: opening,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        willsApiProvider.overrideWithValue(_FakeWillsApi(openAtStep: 5)),
        willProvider('draft-1').overrideWith((ref) async => w),
        witnessesProvider('draft-1').overrideWith((ref) async => const <Witness>[]),
        trusteesProvider('draft-1').overrideWith((ref) async => const <Trustee>[]),
        disclaimerProvider.overrideWith(
          (ref) async => (version: 'v1', text: 'This is a religious tool, not legal advice.'),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: WasiatiTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ReviewSealScreen(willId: 'draft-1'),
      ),
    ));
    // PdfPreview keeps a frame loop running, so pumpAndSettle never returns here.
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));

    // The review card renders the message in quotes. With an empty field the whole block
    // is skipped, which is what made the review screen look bare.
    expect(find.textContaining(opening, findRichText: true), findsWidgets,
        reason: 'the page that seals must show the words it is about to seal');
  });
}
