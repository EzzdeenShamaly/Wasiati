// The will on the page and its two controls.
//
// The owner could not read their will before downloading it: nothing in the app rendered the
// document, and the only export path was a modal that immediately downloaded a file. The
// %-or-fractions choice the spec requires was unreachable too — the server has always
// accepted ?display=, and downloadPdf simply never sent it.
//
// The document renders as LIVE native text (WillDocumentSheet) — ONE view, like the
// prototype; there is no in-app PDF page-view (owner, 27 Jul 2026). These tests drive the
// real card and assert two things: the document itself is on screen without any server
// render, and the two toggles steer the shared choice the Download button reads, so what
// leaves the app matches what was read.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart' show authControllerProvider;
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/assets/application/assets_providers.dart' show assetsProvider;
import 'package:wasiati/features/assets/domain/asset_models.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show willPreviewChoiceProvider, willProvider, willsApiProvider, witnessesProvider, trusteesProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_preview_card.dart';

final _will = Will(
  id: 'w1',
  tier: 'PREMIUM',
  locked: true,
  status: 'SEALED',
  sealedAt: DateTime.utc(2026, 5, 3),
  shariaShares: const [
    ShariaShare(heirRelation: 'WIFE', heirName: 'Zainab', sharePercent: 12.5, basisEn: 'Qur’an 4:12', basisAr: 'النساء ١٢'),
  ],
  witnesses: const [],
);

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(
        AuthUser(id: 'u1', email: 'ahmed@example.com', role: 'USER', region: 'KSA', addressCity: 'Riyadh', addressCountry: 'SA'),
      );
}

class _Api extends WillsApi {
  _Api() : super(Dio());

  /// Every server-side document render the card asked for. There is exactly ONE
  /// view now — the live sheet — so this must stay empty: a PDF is only ever
  /// produced by the gated Download button, never to draw the page.
  final List<({String format, String lang, String display})> previews = [];

  @override
  Future<Uint8List> previewPdf(String willId,
      {String format = 'table', String lang = 'en', String display = 'percent'}) async {
    previews.add((format: format, lang: lang, display: display));
    return Uint8List(0);
  }

  @override
  Future<List<Will>> list() async => const [];
}

Future<_Api> _pump(WidgetTester t, {String locale = 'en', List<EstateAsset> assets = const []}) async {
  final api = _Api();
  t.view.physicalSize = const Size(1100, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      authControllerProvider.overrideWith(_Auth.new),
      willProvider('w1').overrideWith((ref) async => _will),
      assetsProvider('w1').overrideWith((ref) async => assets),
      witnessesProvider('w1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('w1').overrideWith((ref) async => const <Trustee>[]),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: WillPreviewCard(willId: 'w1'))),
    ),
  ));
  await t.pump(); // let the will future resolve
  await t.pump(const Duration(milliseconds: 100));
  return api;
}

void main() {
  testWidgets('the live document renders on arrival — no server render, ever', (t) async {
    final api = await _pump(t);
    expect(find.text('Last Will & Testament'), findsOneWidget);
    expect(find.text('Division of the estate'.toUpperCase()), findsOneWidget);
    expect(api.previews, isEmpty, reason: 'one live view; the PDF exists only as the download');
  });

  testWidgets('exactly the prototype’s two toggle groups are on screen', (t) async {
    await _pump(t);
    expect(find.text('ESTATE FORMAT'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Narrative'), findsOneWidget);
    expect(find.text('SHARES AS'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    expect(find.text('Fraction'), findsOneWidget);
    // The one-view rule: no view switcher (owner, 27 Jul 2026).
    expect(find.text('Page view'), findsNothing);
  });

  testWidgets('Fraction steers the shared choice the Download reads', (t) async {
    // The contract that matters: the toggle must move willPreviewChoiceProvider,
    // which the Download button reads, or the file would silently differ from the
    // document on screen.
    final api = await _pump(t);
    await t.tap(find.text('Fraction'));
    await t.pump(const Duration(milliseconds: 100));

    final ctx = t.element(find.byType(WillPreviewCard));
    final choice = ProviderScope.containerOf(ctx).read(willPreviewChoiceProvider);
    expect(choice.display, 'fraction',
        reason: 'the spec requires a %-or-fractions choice; it must reach the shared state');
    expect(api.previews, isEmpty);
  });

  testWidgets('NARRATIVE is the default — the first document read sounds like a will', (t) async {
    // DECISIONS §29 (owner, 5 Aug 2026): both formats were always built, but the table
    // was the default everywhere, so the prose sat behind a toggle nobody touched. The
    // default IS the decision — pin it, or a refactor quietly puts the inventory
    // printout back in front of every reader.
    await _pump(t, assets: const [
      EstateAsset(
        id: 'a1',
        label: 'Villa — Al Narjis district',
        kind: 'REAL_ESTATE',
        institution: 'Al Rajhi',
        estimatedValue: 2100000,
        currency: 'USD',
      ),
    ]);
    final ctx = t.element(find.byType(WillPreviewCard));
    final choice = ProviderScope.containerOf(ctx).read(willPreviewChoiceProvider);
    expect(choice.format, 'essay');
    // And the sheet renders WILL LANGUAGE, not the table re-flowed with semicolons —
    // "Villa — USD 2,100,000; …" as a paragraph was the owner's exact complaint.
    expect(find.textContaining('I declare that, as of the sealing'), findsOneWidget);
    expect(find.textContaining('held with Al Rajhi'), findsOneWidget);
  });

  testWidgets('the two choices combine rather than clobbering each other', (t) async {
    await _pump(t);
    await t.tap(find.text('Narrative'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Fraction'));
    await t.pump(const Duration(milliseconds: 100));

    final ctx = t.element(find.byType(WillPreviewCard));
    final choice = ProviderScope.containerOf(ctx).read(willPreviewChoiceProvider);
    expect(choice, (format: 'essay', display: 'fraction'));
  });

  testWidgets('the fraction toggle changes the share on the sheet itself', (t) async {
    await _pump(t);
    expect(find.textContaining('12.5'), findsWidgets); // percent by default
    await t.tap(find.text('Fraction'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('1/8'), findsWidgets); // the wife's canonical eighth
  });

  testWidgets('the Arabic locale renders the Arabic document live', (t) async {
    await _pump(t, locale: 'ar');
    expect(find.text('الوصية الأخيرة'), findsOneWidget); // doc title
    expect(find.text('قسمة التركة'), findsOneWidget); // division heading
  });
}
