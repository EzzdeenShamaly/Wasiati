// WHICH grandmother survived has to be asked, because they are excluded by different people.
//
// The mother excludes BOTH grandmothers. The father excludes only his OWN mother — the
// paternal one — while the maternal grandmother takes her sixth alongside him.
//
// The create flow asked one question, "Grandmother living", and always built a MATERNAL
// grandmother. So an owner whose surviving grandmother was PATERNAL, with their father also
// alive, was handed a sixth she is not entitled to and the father was short by exactly that
// amount. A wrong division, printed and sealed, produced by a question that never
// distinguished the two people. The arithmetic was never the bug — the input was.
//
// These drive _buildHeirs through the real screen rather than testing the engine, because
// the engine was already correct: give it PATERNAL_GRANDMOTHER + FATHER and it excludes her.
// Nothing ever gave it that.

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
  _Api(this.draft) : super(Dio());
  final Map<String, dynamic> draft;

  /// The last snapshot the screen autosaved — how we read back what it built.
  Map<String, dynamic>? saved;

  Will get _d => Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': 1,
        'sex': 'male',
        'madhhab': 'JUMHUR',
        ...draft,
      });
  @override
  Future<List<Will>> list() async => [_d];
  @override
  Future<Will> getOne(String id) async => _d;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _d;
  @override
  Future<Will> updateDraft(String w, Map<String, dynamic> s) async {
    saved = s;
    return _d;
  }

  @override
  Future<List<HeirContact>> heirContacts(String w) async => const [];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

Future<_Api> _open(WidgetTester t, Map<String, dynamic> draft) async {
  final api = _Api(draft);
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'x')),
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
  return api;
}

void main() {
  testWidgets('both grandmothers are asked about separately', (t) async {
    await _open(t, const {});
    await t.tap(find.textContaining('extended family'));
    await t.pumpAndSettle();
    expect(find.textContaining("mother’s mother"), findsOneWidget);
    expect(find.textContaining("father’s mother"), findsOneWidget);
  });

  testWidgets('a PATERNAL grandmother is excluded by a living father', (t) async {
    // The bug: she used to be built as maternal and handed 1/6 the father was owed.
    await _open(t, const {'father': true, 'gmPaternal': true, 'extended': true, 'sons': 1});
    // Assert on the HEIR, not on a percentage. The father himself takes a sixth alongside a
    // son, so 16.67 legitimately appears on this screen and says nothing about a grandmother.
    //
    // And assert NO grandmother of EITHER side appears — not merely that the paternal label
    // is absent. Checking only the paternal label passes while the bug is present, because
    // the bug's whole nature is relabelling her as maternal. Mutation-checked: reverting the
    // fix fails this line and only this line.
    expect(find.textContaining('Grandmother (paternal)'), findsNothing,
        reason: 'a father excludes his own mother — she must not appear in the division');
    expect(find.textContaining('Grandmother (maternal)'), findsNothing,
        reason: 'and she must not be silently re-labelled as the OTHER grandmother, which is '
            'exactly what the single-toggle bug did — handing her a sixth owed to the father');
  });

  testWidgets('a MATERNAL grandmother still inherits alongside a living father', (t) async {
    // The other half of the rule: the father does NOT exclude his wife's mother.
    await _open(t, const {'father': true, 'gmMaternal': true, 'extended': true, 'sons': 1});
    expect(find.textContaining('Grandmother (maternal)'), findsWidgets,
        reason: 'the father does not exclude his wife’s mother — she takes her sixth');
  });

  testWidgets('an older draft\'s single flag is restored as MATERNAL, its original meaning', (t) async {
    // The one toggle always built a maternal grandmother. A saved draft must not silently
    // change meaning just because the question got better.
    final api = await _open(t, const {'grandmother': true, 'extended': true});
    await t.tap(find.textContaining('extended family'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    expect(api.saved?['gmMaternal'], isTrue);
    expect(api.saved?['gmPaternal'], isNot(true));
  });

  testWidgets('the new answers are persisted separately', (t) async {
    final api = await _open(t, const {'extended': true});
    // The disclosure is derived from its contents, so on an empty draft it starts closed.
    await t.tap(find.textContaining('extended family'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining("father’s mother"));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1));
    expect(api.saved?['gmPaternal'], isTrue);
    expect(api.saved?['gmMaternal'], isNot(true));
  });
}
