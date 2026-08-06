import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart';
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// An invite that reached NOBODY must be visible to the owner.
///
/// addWitness/addTrustee return `notified: boolean` (backend a0f96e4): `false`
/// means no SMS was dispatched and no email was on file, so that person will
/// never confirm, the will never reaches its witness quorum, and release can
/// never be gated on the trustee. The owner is the only one who can fix it and
/// was never told. So these assert the CALL and the surfaced state — not that a
/// label renders. A label-only test passes against a dead handler, which is the
/// exact bug being fixed.
class _RecordingWillsApi extends WillsApi {
  _RecordingWillsApi() : super(Dio());

  final calls = <String>[];
  bool notified = true;
  final witnessRows = <Witness>[];
  final trusteeRows = <Trustee>[];
  var _n = 0;

  @override
  Future<({String id, bool notified})> addWitness(String willId,
      {required String fullName, required String phone, String? email}) async {
    final id = 'wit-${++_n}';
    calls.add('POST /wills/$willId/witnesses name=$fullName phone=$phone email=${email ?? ''}');
    witnessRows.add(Witness(id: id, fullName: fullName, phone: phone, status: 'PENDING'));
    return (id: id, notified: notified);
  }

  @override
  Future<({String id, bool notified})> addTrustee(String willId,
      {required String fullName, required String phone, String? email}) async {
    final id = 'tr-${++_n}';
    calls.add('POST /wills/$willId/trustees name=$fullName phone=$phone email=${email ?? ''}');
    trusteeRows.add(Trustee(id: id, fullName: fullName, phone: phone, status: 'PENDING'));
    return (id: id, notified: notified);
  }
}

const _draft = Will(id: 'w1', tier: 'STANDARD', locked: false, status: 'DRAFT');

Future<_RecordingWillsApi> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final api = _RecordingWillsApi();
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      willProvider.overrideWith((ref, id) async => _draft),
      witnessesProvider.overrideWith((ref, id) async => List.of(api.witnessRows)),
      trusteesProvider.overrideWith((ref, id) async => List.of(api.trusteeRows)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(initialLocation: '/wills/w1', routes: [
        GoRoute(path: '/wills/:id', builder: (_, s) => WillDetailScreen(willId: s.pathParameters['id']!)),
        GoRoute(path: '/wills', builder: (_, __) => const Scaffold()),
      ]),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

Future<void> _addPerson(WidgetTester t, String addButton,
    {required String name, required String phone, String? email}) async {
  await t.ensureVisible(find.text(addButton));
  await t.tap(find.text(addButton));
  await t.pumpAndSettle();
  final l = await AppLocalizations.delegate.load(const Locale('en'));
  await t.enterText(find.widgetWithText(TextField, l.wdFullName), name);
  await t.enterText(find.widgetWithText(TextField, l.wdPhone), phone);
  if (email != null) {
    await t.enterText(find.widgetWithText(TextField, l.wdEmailOptional), email);
  }
  await t.tap(find.text(l.commonAdd));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('adding a witness CALLS POST /wills/:id/witnesses with the email', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _addPerson(t, l.wdAddWitnessBtn,
        name: 'Omar Ali', phone: '+15551230001', email: 'omar@example.com');

    expect(api.calls, ['POST /wills/w1/witnesses name=Omar Ali phone=+15551230001 email=omar@example.com'],
        reason: 'the dialog must reach the endpoint, and must forward the email — '
            'without it a wrong number means the invite has no second channel');
  });

  testWidgets('notified:false surfaces "we could not reach them" on the witness row', (t) async {
    final api = await _pump(t);
    api.notified = false;
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _addPerson(t, l.wdAddWitnessBtn, name: 'Omar Ali', phone: '+15551230001');

    expect(find.text('Omar Ali'), findsOneWidget);
    expect(find.text(l.wdInviteUnreached), findsOneWidget,
        reason: 'nobody was reached — hidden, the witness never confirms and the '
            'will never seals, and only the owner can fix it');
    // The row is still valid: the resend path stays available, nothing alarming.
    expect(find.text(l.wdSendCode), findsOneWidget);
  });

  testWidgets('notified:false surfaces the same state on the trustee row', (t) async {
    final api = await _pump(t);
    api.notified = false;
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _addPerson(t, l.wdAddTrusteeBtn, name: 'Bilal Khan', phone: '+15551230002');

    expect(api.calls.single, contains('POST /wills/w1/trustees'));
    expect(find.text(l.wdInviteUnreached), findsOneWidget);
  });

  testWidgets('notified:true shows the normal pending status, not the warning', (t) async {
    await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await _addPerson(t, l.wdAddWitnessBtn, name: 'Sara Noor', phone: '+15551230003');

    expect(find.text(l.wdStatusPending), findsOneWidget);
    expect(find.text(l.wdInviteUnreached), findsNothing,
        reason: 'a delivered invite must not false-alarm the owner');
  });
}
