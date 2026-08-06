import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/features/commerce/application/commerce_providers.dart';
import 'package:wasiati/features/commerce/data/commerce_api.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';
import 'package:wasiati/features/commerce/presentation/admin/admin_console_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// Edit / Archive / Reinstate on the promotions tab. The backend has had PATCH
/// and archive/reinstate since d9ee1f0 while the console only offered NEW and a
/// delete button — the exact build-it-server-side-and-never-wire-it failure this
/// suite family exists to catch. So these assert the controls REACH their
/// endpoints, with the payload the backend contract expects (explicit null =
/// clear a limit; absent = leave unchanged).
class _RecordingCommerceApi extends CommerceApi {
  _RecordingCommerceApi(this.promos) : super(Dio());
  final List<Promotion> promos;
  final updated = <(String, Map<String, dynamic>)>[];
  final archived = <String>[];
  final reinstated = <String>[];

  @override
  Future<List<PricingPlan>> adminListPlans() async => const [];
  @override
  Future<List<Offer>> adminListOffers() async => const [];
  @override
  Future<List<Promotion>> adminListPromotions() async => promos;
  @override
  Future<void> adminUpdatePromotion(String id, Map<String, dynamic> patch) async {
    updated.add((id, patch));
  }

  @override
  Future<void> adminDeletePromotion(String id) async => archived.add(id);
  @override
  Future<void> adminReinstatePromotion(String id) async => reinstated.add(id);
}

/// The seeded launch code as it actually ships: first-time-only, NO cap, NO
/// expiry — the row the owner most urgently needs to be able to edit.
const _launch25 = Promotion(
  id: 'p1',
  code: 'LAUNCH25',
  type: 'PERCENT',
  value: 25,
  active: true,
  timesRedeemed: 3,
  firstTimeOnly: true,
);

const _archivedPromo = Promotion(
  id: 'p2',
  code: 'EID10',
  type: 'PERCENT',
  value: 10,
  active: false,
  timesRedeemed: 40,
);

Future<_RecordingCommerceApi> _pumpPromosTab(WidgetTester t, {List<Promotion>? promos}) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _RecordingCommerceApi(promos ?? [_launch25]);
  await t.pumpWidget(ProviderScope(
    overrides: [commerceApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AdminConsoleScreen(),
    ),
  ));
  await t.pumpAndSettle();
  final l = await AppLocalizations.delegate.load(const Locale('en'));
  await t.tap(find.text(l.adminCommerceTabPromotions));
  await t.pumpAndSettle();
  return api;
}

void main() {
  late AppLocalizations l;
  setUpAll(() async => l = await AppLocalizations.delegate.load(const Locale('en')));

  testWidgets('Edit opens pre-filled and Save PATCHes the promotion', (t) async {
    final api = await _pumpPromosTab(t);

    await t.tap(find.byIcon(Icons.edit_outlined));
    await t.pumpAndSettle();
    // Pre-filled from the row, not a blank NEW dialog.
    expect(find.widgetWithText(TextField, 'LAUNCH25'), findsOneWidget);
    expect(find.text(l.adminPromoEditTitle), findsOneWidget);

    // Give the uncapped launch code the cap it shipped without.
    // Fields: [0] code, [1] value, [2] max redemptions (the dropdown is not a TextField).
    await t.enterText(find.byType(TextField).at(2), '500');
    await t.tap(find.text(l.commonSave));
    await t.pumpAndSettle();

    final (id, patch) = api.updated.single;
    expect(id, 'p1');
    expect(patch['maxRedemptions'], 500);
    expect(patch['code'], 'LAUNCH25');
    // The switch pre-filled true must survive the round-trip — PATCH omitting it
    // would be fine, but sending false would silently un-gate the code.
    expect(patch['firstTimeOnly'], isTrue);
  });

  testWidgets('an emptied limit is sent as an EXPLICIT null, the backend contract for clear', (t) async {
    final api = await _pumpPromosTab(t);

    await t.tap(find.byIcon(Icons.edit_outlined));
    await t.pumpAndSettle();
    await t.tap(find.text(l.commonSave));
    await t.pumpAndSettle();

    final (_, patch) = api.updated.single;
    // LAUNCH25 has no dates and no cap; the edit dialog shows every limit, so
    // absent-from-the-map would be wrong here — these must be null ON PURPOSE
    // (an omitted key would also stop a future clear from ever working).
    expect(patch.containsKey('endsAt'), isTrue);
    expect(patch['endsAt'], isNull);
    expect(patch.containsKey('startsAt'), isTrue);
    expect(patch['startsAt'], isNull);
    expect(patch.containsKey('maxRedemptions'), isTrue);
    expect(patch['maxRedemptions'], isNull);
  });

  testWidgets('Archive hits DELETE (which archives server-side) and says it is reversible', (t) async {
    final api = await _pumpPromosTab(t);

    expect(find.byIcon(Icons.unarchive_outlined), findsNothing, reason: 'active row: no reinstate');
    await t.tap(find.byIcon(Icons.archive_outlined));
    await t.pumpAndSettle();

    expect(api.archived, ['p1']);
    expect(find.text(l.adminPromoArchived), findsOneWidget,
        reason: 'The snack must say archived-and-reinstatable — the old trash-can '
            'promised a permanence DELETE no longer has.');
  });

  testWidgets('an archived row offers Reinstate, which hits the reinstate endpoint', (t) async {
    final api = await _pumpPromosTab(t, promos: [_archivedPromo]);

    expect(find.byIcon(Icons.archive_outlined), findsNothing, reason: 'archived row: no archive');
    await t.tap(find.byIcon(Icons.unarchive_outlined));
    await t.pumpAndSettle();

    expect(api.reinstated, ['p2']);
    expect(api.archived, isEmpty);
  });
}
