// The extended-family section on create-will step 1 stays HIDDEN until it is opened.
//
// The owner reported it showing when it should not. The gate itself was never broken —
// _showExtended starts false and 'if (_showExtended)' works. What broke the promise was
// PERSISTENCE: _snapshot wrote 'extended': _showExtended into the draft and _restore read
// it back, so a single click was permanent. Most owners have no extended heirs at all, yet
// once opened they met the grandparents/siblings/uncles/cousins block expanded on every
// later visit to that will. The prototype does not persist this flag either.
//
// It is now DERIVED on restore: open exactly when the section holds something. Forcing it
// closed unconditionally would hide heirs the owner actually entered — and those heirs
// still count toward the fara'id shares, so hiding them would be worse than the bug.

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

class _FakeWillsApi extends WillsApi {
  final Map<String, dynamic> draft;
  _FakeWillsApi(this.draft) : super(Dio());

  /// The last snapshot the screen tried to autosave — this is how we prove the
  /// disclosure flag no longer leaves the screen.
  Map<String, dynamic>? lastSaved;

  Will get _d => Will(
        id: 'draft-1',
        tier: 'STANDARD',
        locked: false,
        status: 'DRAFT',
        draftState: {'step': 1, 'sex': 'male', 'sons': 1, 'madhhab': 'JUMHUR', ...draft},
      );

  @override
  Future<List<Will>> list() async => [_d];
  @override
  Future<Will> getOne(String id) async => _d;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _d;
  @override
  Future<Will> updateDraft(String willId, Map<String, dynamic> draftState) async {
    lastSaved = draftState;
    return _d;
  }

  @override
  Future<List<HeirContact>> heirContacts(String willId) async => const [];
  @override
  Future<List<Witness>> witnesses(String willId) async => const [];
  @override
  Future<List<Trustee>> trustees(String willId) async => const [];
}

Future<_FakeWillsApi> _open(WidgetTester t, Map<String, dynamic> draft) async {
  final api = _FakeWillsApi(draft);
  t.view.physicalSize = const Size(1000, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
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

/// The counters that live inside the disclosure. If any is on screen, it is open.
Finder get _insideSection => find.textContaining('Brothers');

void main() {
  testWidgets('a fresh draft opens with the extended family hidden', (t) async {
    await _open(t, const {});
    expect(_insideSection, findsNothing);
  });

  testWidgets('tapping the toggle reveals it', (t) async {
    await _open(t, const {});
    expect(_insideSection, findsNothing);

    await t.tap(find.textContaining('extended family'));
    await t.pumpAndSettle();
    expect(_insideSection, findsWidgets, reason: 'the disclosure must open on tap');
  });

  testWidgets('an EMPTY section does not reopen on the next visit — the reported bug', (t) async {
    // Exactly the state a stale draft was left in: the flag was saved as true while every
    // extended value is empty. Restoring that used to reopen the panel forever.
    final api = await _open(t, const {'extended': true});
    expect(_insideSection, findsNothing,
        reason: 'nothing is in the section, so it must stay closed however the draft was saved');

    // …and the flag never leaves the screen again, so it cannot be persisted anew.
    await t.tap(find.textContaining('extended family'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 1)); // let the 600ms autosave debounce fire
    expect(api.lastSaved, isNotNull, reason: 'the screen should have autosaved after a change');
    expect(api.lastSaved!.containsKey('extended'), isFalse,
        reason: 'disclosure state is not will content and must not be written to the draft');
  });

  testWidgets('a section that HOLDS heirs opens, so entered data is never hidden', (t) async {
    // Those brothers count toward the fara'id shares. Collapsing them out of sight would
    // be a worse defect than the one being fixed.
    await _open(t, const {'brothers': 2});
    expect(_insideSection, findsWidgets);
  });

  testWidgets('each extended field on its own is enough to open it', (t) async {
    for (final seed in const [
      {'grandfather': true},
      {'grandmother': true},
      {'sisters': 1},
      {'uncles': 1},
      {'cousins': 1},
    ]) {
      await _open(t, seed);
      expect(_insideSection, findsWidgets, reason: 'restoring $seed must open the section');
    }
  });
}
