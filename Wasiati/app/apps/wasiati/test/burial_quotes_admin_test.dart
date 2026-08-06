import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/features/burial/application/burial_providers.dart';
import 'package:wasiati/features/burial/data/burial_api.dart';
import 'package:wasiati/features/burial/domain/burial_models.dart';
import 'package:wasiati/features/burial/presentation/burial_quotes_admin_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The burial-quote loop's admin half. The disease this guards against: the
/// request flow was built server-side and dead-ended — a user pressed "Request a
/// real quote", the row flipped to QUOTE_REQUESTED, and NO surface could list or
/// answer it. Following entry_points_reachable_test.dart, these assert the
/// Record-quote control ACTUALLY CALLS the manual-quote endpoint, not merely
/// that a card renders.
class _RecordingBurialApi extends BurialApi {
  _RecordingBurialApi(this.queue) : super(Dio());
  final List<BurialQuoteRequest> queue;
  final submitted = <(String, double, String?)>[];

  @override
  Future<List<BurialQuoteRequest>> adminPendingQuotes() async => queue;

  @override
  Future<void> adminSubmitQuote(String estimateId, {required double amount, String? notes}) async {
    submitted.add((estimateId, amount, notes));
  }
}

BurialQuoteRequest _request({String status = 'QUOTE_REQUESTED', double? quoted}) => BurialQuoteRequest(
      estimate: BurialEstimate(
        id: 'be1',
        city: 'Dearborn',
        currency: 'USD',
        baseAmount: 9000,
        projectedAmount: 13300,
        inflationRatePercent: 4,
        projectionYears: 10,
        baseYear: 2026,
        status: status,
        manualQuoteAmount: quoted,
      ),
      userEmail: 'client@x.com',
      userPhone: '+13130001111',
      userRegion: 'US',
    );

Future<_RecordingBurialApi> _pump(WidgetTester t, {List<BurialQuoteRequest>? queue}) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final api = _RecordingBurialApi(queue ?? [_request()]);
  await t.pumpWidget(ProviderScope(
    overrides: [burialApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BurialQuotesAdminScreen(),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

void main() {
  late AppLocalizations l;
  setUpAll(() async => l = await AppLocalizations.delegate.load(const Locale('en')));

  testWidgets('a waiting request is listed with who and where to call', (t) async {
    await _pump(t);

    expect(find.text('Dearborn, US'), findsOneWidget);
    expect(find.textContaining('client@x.com'), findsOneWidget);
    expect(find.text(l.bqStatusRequested), findsOneWidget);
  });

  testWidgets('Record quote actually POSTs the manual quote, amount and notes intact', (t) async {
    final api = await _pump(t);

    await t.tap(find.text(l.bqRecordQuote));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '11500');
    await t.enterText(find.byType(TextField).last, 'Islamic Center of Dearborn, incl. plot');
    await t.tap(find.text(l.commonSave));
    await t.pumpAndSettle();

    expect(api.submitted, [('be1', 11500.0, 'Islamic Center of Dearborn, incl. plot')],
        reason: 'The dialog must reach POST /burial-estimates/:id/manual-quote — '
            'a control that only renders is exactly the bug this screen exists to end.');
  });

  testWidgets('a non-numeric amount is refused without calling the endpoint', (t) async {
    final api = await _pump(t);

    await t.tap(find.text(l.bqRecordQuote));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'soon');
    await t.tap(find.text(l.commonSave));
    await t.pumpAndSettle();

    expect(find.text(l.bqErrorAmountRequired), findsOneWidget);
    expect(api.submitted, isEmpty);
  });

  testWidgets('an already-QUOTED row stays correctable and pre-fills the recorded amount', (t) async {
    final api = await _pump(t, queue: [_request(status: 'QUOTED', quoted: 11500)]);

    expect(find.text(l.bqStatusQuoted), findsOneWidget);
    await t.tap(find.text(l.bqRecordQuote));
    await t.pumpAndSettle();

    // Pre-filled with what was recorded, so a typo is a two-keystroke fix.
    expect(find.widgetWithText(TextField, '11500'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '10500');
    await t.tap(find.text(l.commonSave));
    await t.pumpAndSettle();

    expect(api.submitted.single.$2, 10500.0);
  });

  testWidgets('an empty queue says so instead of showing a blank page', (t) async {
    await _pump(t, queue: []);
    expect(find.text(l.bqNoPending), findsOneWidget);
  });
}
