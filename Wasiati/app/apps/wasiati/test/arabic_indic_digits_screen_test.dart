import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider, willsListProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';
import 'package:wasiati/features/wills/presentation/wills_list_screen.dart';

/// The helper is unit-tested in localize_digits_test; this pins the INTEGRATION — that the
/// call sites are actually wrapped — on the richest screen. The wills-list meta row alone
/// composes four computed numbers (heirs, bequest %, witness counts, an updated date), each
/// via a different l10n key. Under `ar` every one must render Arabic-Indic; a single Western
/// digit anywhere on the screen means a number slipped through unwrapped.
///
/// Heirs are set to 3, not 2: cwHeirCount is an ICU plural whose =1/=2 branches spell the
/// number as a word ("وارثان") — only the `few`/`other` branches actually emit a digit, so a
/// smaller fixture would not exercise the wrap it is meant to guard.
final _will = Will(
  id: 'w1',
  tier: 'PREMIUM',
  locked: true,
  status: 'SEALED',
  requiredWitnesses: 2,
  sealedAt: DateTime(2026, 5, 3),
  updatedAt: DateTime(2026, 5, 3),
  witnesses: const [
    Witness(id: 'a', fullName: '', phone: '', status: 'CONFIRMED'),
    Witness(id: 'b', fullName: '', phone: '', status: 'SIGNED'),
  ],
  bequests: const [Bequest(id: 'x', beneficiaryName: 'Charity', sharePercent: 25)],
  shariaShares: const [
    ShariaShare(heirRelation: 'SON', heirName: '', sharePercent: 40),
    ShariaShare(heirRelation: 'DAUGHTER', heirName: '', sharePercent: 20),
    ShariaShare(heirRelation: 'WIFE', heirName: '', sharePercent: 12),
  ],
);

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  testWidgets('the wills list renders every computed number in Arabic-Indic under ar', (t) async {
    t.view.physicalSize = const Size(520, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(ProviderScope(
      overrides: [willsListProvider.overrideWith((ref) async => [_will])],
      child: MaterialApp(
        locale: const Locale('ar'),
        theme: WasiatiTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WillsListScreen(),
      ),
    ));
    await t.pumpAndSettle();

    // Every visible string on the screen, in one bag.
    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList();
    final all = texts.join('\n');

    // The screen genuinely rendered numbers (guards against the fixture silently showing none).
    expect(RegExp(r'[٠-٩]').hasMatch(all), isTrue,
        reason: 'expected Arabic-Indic digits somewhere on the list; got:\n$all');

    // …and not one of them is Western. A leaked ASCII digit is an unwrapped call site.
    final leaked = texts.where((s) => RegExp(r'[0-9]').hasMatch(s)).toList();
    expect(leaked, isEmpty,
        reason: 'these strings still carry Western digits under ar — wrap them in context.digits():\n'
            '${leaked.join('\n')}');
  });

  // The list was the only screen this guard covered, and the create flow's review step —
  // the densest numeric screen in the app — was not. It showed every fara'id share, the
  // bequest percentage, the donut label, the estate totals and the numbered heir names
  // ("الابن 1") in Western digits, right beside Arabic-Indic Qur'anic citations from the
  // ARB. Same defect the helper exists to prevent, on the screen where the numbers matter
  // most: this is what an owner reads before sealing.
  testWidgets('the create-will review step renders every computed number in Arabic-Indic under ar',
      (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(ProviderScope(
      overrides: [
        willsApiProvider.overrideWithValue(_ReviewDraftApi()),
        disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'وصيتي أداة دينية.')),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        theme: WasiatiTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CreateWillScreen(),
      ),
    ));
    await t.pumpAndSettle();

    final texts = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList();
    expect(RegExp(r'[٠-٩]').hasMatch(texts.join('\n')), isTrue,
        reason: 'the review step rendered no digits at all — the fixture is not reaching it');

    final leaked = texts.where((s) => RegExp(r'[0-9]').hasMatch(s)).toList();
    expect(leaked, isEmpty,
        reason: 'these strings still carry Western digits under ar — wrap them in context.digits():\n'
            '${leaked.join('\n')}');
  });
}

/// A draft restored straight onto the review step (6), with heirs and a bequest so the
/// shares, the donut and the totals all have numbers to render.
class _ReviewDraftApi extends WillsApi {
  _ReviewDraftApi() : super(Dio());
  Will get _d => const Will(id: 'draft-1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': 6,
        'sex': 'male',
        'wives': 1,
        'sons': 2,
        'daughters': 1,
        'mother': true,
        'madhhab': 'JUMHUR',
        'bequest': {'name': 'أيتام الحي', 'third': 40.0},
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
