// The heir registry opens collapsed, and says what each closed card still needs.
//
// A will with four wives and a dozen children puts twenty-odd cards on this step, each with
// a name, a phone, an email and — for a minor — a guardian block. Expanded by default that
// is several screens of identical fields with no way to see the shape of the family.
//
// Collapsing is only safe because the closed card keeps answering the step's real question.
// Sealing refuses while any heir is missing a name, phone or email, so a card that hid its
// completeness would turn a twenty-heir will into a hunt for the one that is short. Every
// test here that checks a collapsed row also checks it still reports its state.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@wasiati.test', region: 'US', role: 'USER'));
}

class _Api extends WillsApi {
  _Api() : super(Dio());
  Will get _d => const Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': 2,
        'sex': 'male',
        'wives': 2,
        'sons': 2,
        'madhhab': 'JUMHUR',
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
  Future<List<HeirContact>> heirContacts(String w) async => const [
        HeirContact(id: 'h1', relation: 'wife', name: 'Layla Mahmoud', phone: '+1 555 0100', email: 'l@x.test'),
        HeirContact(id: 'h2', relation: 'son', name: 'Yusuf', phone: '+1 555 0102', email: 'y@x.test'),
        HeirContact(id: 'h3', relation: 'mother', name: '', phone: '', email: ''),
      ];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

Future<void> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(1200, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsApiProvider.overrideWithValue(_Api()),
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
}

/// The per-heir editable fields only exist while a card is open, so counting them counts
/// open cards. Three fields per heir (name, phone, email) plus the step's own inputs.
int _heirFieldCount(WidgetTester t) => t.widgetList(find.byType(TextField)).length;

void main() {
  testWidgets('every card starts collapsed', (t) async {
    await _open(t);
    expect(find.text('Layla Mahmoud'), findsOneWidget, reason: 'the summary names each heir');
    expect(find.text('Yusuf'), findsOneWidget);
    // No heir field is on screen, so nothing is expanded.
    expect(_heirFieldCount(t), 0, reason: 'collapsed cards render no editable fields');
  });

  testWidgets('a collapsed card still says whether it needs details', (t) async {
    await _open(t);
    // h3 (mother) has no name, phone or email — sealing will refuse until it does, so the
    // closed card has to say so without being opened.
    expect(find.text('Needs details'), findsOneWidget);
    // ...and the two complete ones do not cry wolf.
    expect(find.text('Mother'), findsOneWidget, reason: 'an unnamed heir falls back to its relation');
  });

  testWidgets('tapping a card opens only that one', (t) async {
    await _open(t);
    await t.tap(find.text('Layla Mahmoud'));
    await t.pumpAndSettle();
    expect(_heirFieldCount(t), 3, reason: 'exactly one card open = name + phone + email');
  });

  testWidgets('Expand all opens every card, and then collapses them again', (t) async {
    await _open(t);
    expect(find.text('Expand all'), findsOneWidget);

    await t.tap(find.text('Expand all'));
    await t.pumpAndSettle();
    expect(_heirFieldCount(t), 9, reason: 'three heirs x three fields');

    // The same control now offers the opposite.
    expect(find.text('Collapse all'), findsOneWidget);
    await t.tap(find.text('Collapse all'));
    await t.pumpAndSettle();
    expect(_heirFieldCount(t), 0);
  });

  testWidgets('an open card can be closed from its own header', (t) async {
    await _open(t);
    await t.tap(find.text('Yusuf'));
    await t.pumpAndSettle();
    expect(_heirFieldCount(t), 3);

    await t.tap(find.byIcon(Icons.expand_less));
    await t.pumpAndSettle();
    expect(_heirFieldCount(t), 0, reason: 'the card closes without touching the others');
  });
}
