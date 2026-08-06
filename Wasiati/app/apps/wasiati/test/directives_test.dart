// The directives beyond the will (financial POA / healthcare directive) on the
// Wills page. Each card expands INLINE into a prepare-&-sign form; "Save & sign"
// stays disabled until every field is filled (the HCD also needs its treatment
// wishes), and a signed document flips the card to a SIGNED pill + agent line.
// Premium+ is a soft sell — a lower tier still sees the cards, with an upgrade
// nudge in place of the button, never a wall.
//
// These pump the real WillsListScreen with a fake WillsApi and a stubbed
// entitlement, so they exercise the actual _DocCard/_DirectiveForm widgets (both
// private) exactly as the screen wires them — the same path the buttons trigger.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/commerce/application/entitlement_providers.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart' show willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/wills_list_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Api extends WillsApi {
  _Api({List<DirectiveDoc> docs = const []})
      : _docs = List.of(docs),
        super(Dio());

  List<DirectiveDoc> _docs;
  int saveCalls = 0;
  String? lastType;
  String? lastName;
  String? lastWishes;

  // One DRAFT will so the list renders its grid (an empty list shows the empty
  // state, which omits the directives section entirely).
  @override
  Future<List<Will>> list() async => const [Will(id: 'w1', tier: 'PREMIUM', locked: false, status: 'DRAFT')];

  @override
  Future<List<DirectiveDoc>> directives() async => _docs;

  @override
  Future<DirectiveDoc> saveDirective(
    String type, {
    required String agentName,
    required String agentPhone,
    required String agentEmail,
    String? wishes,
  }) async {
    saveCalls++;
    lastType = type;
    lastName = agentName;
    lastWishes = wishes;
    final doc = DirectiveDoc(
      id: 'saved-$type',
      type: type,
      agentName: agentName,
      agentPhone: agentPhone,
      agentEmail: agentEmail,
      wishes: wishes ?? '',
      status: 'SIGNED',
    );
    // Mirror the server upsert: one row per type, refetched after invalidation.
    _docs = [..._docs.where((d) => d.type != type), doc];
    return doc;
  }
}

Future<_Api> _open(WidgetTester t, {bool entitled = true, List<DirectiveDoc> docs = const []}) async {
  t.view.physicalSize = const Size(1200, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _Api(docs: docs);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      entitlementProvider.overrideWith((ref) async => {
            'tier': entitled ? 'ULTIMATE' : 'STANDARD',
            'features': {'directives': entitled},
          }),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WillsListScreen(),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

/// The "Save & sign" button, so a test can read its enabled/disabled state.
FilledButton _save(WidgetTester t) => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save & sign'));

void main() {
  testWidgets('entitled + unsigned: both cards show NOT STARTED with a Prepare & sign, forms closed', (t) async {
    await _open(t, entitled: true, docs: const []);
    expect(find.text('Financial power of attorney'), findsOneWidget);
    expect(find.text('Healthcare directive'), findsOneWidget);
    expect(find.text('NOT STARTED'), findsNWidgets(2));
    expect(find.text('Prepare & sign'), findsNWidgets(2));
    // Nothing is expanded, so no form fields are on screen.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Prepare & sign opens the POA form; Save & sign stays disabled until every field is filled', (t) async {
    await _open(t, entitled: true);
    await t.tap(find.text('Prepare & sign').first); // POA is the first card
    await t.pumpAndSettle();

    // POA has no treatment-wishes field: agent name + phone + email only.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(_save(t).onPressed, isNull, reason: 'disabled while empty');

    await t.enterText(find.byType(TextField).at(0), 'Fatima Al-Rashid');
    await t.enterText(find.byType(TextField).at(1), '+1 555 0100');
    await t.pump();
    expect(_save(t).onPressed, isNull, reason: 'still missing the email');

    await t.enterText(find.byType(TextField).at(2), 'fatima@example.test');
    await t.pump();
    expect(_save(t).onPressed, isNotNull, reason: 'all three filled -> enabled');
  });

  testWidgets('the healthcare directive also gates on its treatment wishes', (t) async {
    await _open(t, entitled: true);
    await t.tap(find.text('Prepare & sign').at(1)); // HCD is the second card
    await t.pumpAndSettle();

    // Agent trio + the extra treatment-wishes field.
    expect(find.byType(TextField), findsNWidgets(4));

    await t.enterText(find.byType(TextField).at(0), 'Zainab Al-Harbi');
    await t.enterText(find.byType(TextField).at(1), '+1 555 0102');
    await t.enterText(find.byType(TextField).at(2), 'zainab@example.test');
    await t.pump();
    expect(_save(t).onPressed, isNull, reason: 'agent complete but wishes still empty');

    await t.enterText(find.byType(TextField).at(3), 'no prolonged life support');
    await t.pump();
    expect(_save(t).onPressed, isNotNull, reason: 'wishes supplied -> enabled');
  });

  testWidgets('a signed directive shows the SIGNED pill, the agent line and an Edit action', (t) async {
    await _open(t, entitled: true, docs: const [
      DirectiveDoc(
        id: 'p1',
        type: 'POA',
        agentName: 'Fatima Al-Rashid',
        agentPhone: '+1 555 0100',
        agentEmail: 'f@example.test',
        status: 'SIGNED',
      ),
    ]);
    expect(find.text('SIGNED'), findsOneWidget);
    expect(find.text('Agent: Fatima Al-Rashid · witnessed digitally'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget, reason: 'a signed card offers Edit, not Prepare');
    // The still-unsigned HCD keeps its Prepare & sign + NOT STARTED.
    expect(find.text('Prepare & sign'), findsOneWidget);
    expect(find.text('NOT STARTED'), findsOneWidget);
  });

  testWidgets('below Premium the cards still show, soft-selling instead of walling', (t) async {
    await _open(t, entitled: false, docs: const []);
    expect(find.text('Financial power of attorney'), findsOneWidget);
    expect(find.text('Healthcare directive'), findsOneWidget);
    // Soft sell on BOTH cards: upgrade chip + nudge + a route to plans...
    expect(find.text('Premium feature'), findsNWidgets(2));
    expect(find.text('Included with Premium and Ultimate.'), findsNWidgets(2));
    expect(find.text('See plans'), findsNWidgets(2));
    // ...and crucially NO way to open the form — the wall is the absence of the button.
    expect(find.text('Prepare & sign'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Save & sign calls the API and the card flips to signed', (t) async {
    final api = await _open(t, entitled: true, docs: const []);
    await t.tap(find.text('Prepare & sign').first); // POA
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).at(0), 'Omar Basha');
    await t.enterText(find.byType(TextField).at(1), '+1 555 9999');
    await t.enterText(find.byType(TextField).at(2), 'omar@example.test');
    await t.pump();

    await t.tap(find.widgetWithText(FilledButton, 'Save & sign'));
    // Let the save future resolve, the provider refetch, and the snackbar timer drain.
    await t.pumpAndSettle(const Duration(seconds: 5));

    expect(api.saveCalls, 1);
    expect(api.lastType, 'POA');
    expect(api.lastName, 'Omar Basha');
    expect(api.lastWishes, isNull, reason: 'a POA carries no treatment wishes');
    // The card reflects the freshly-signed document.
    expect(find.text('Agent: Omar Basha · witnessed digitally'), findsOneWidget);
    expect(find.text('SIGNED'), findsOneWidget);
  });
}
