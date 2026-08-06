// You can read the actual will before you seal it.
//
// Both places a will can be sealed used to show only a SUMMARY of it — shares, people,
// totals — so the last thing an owner saw before pressing an irreversible button was a
// description of the document rather than the document. The server has always been able to
// render an unsealed will (`GET /wills/:id/pdf/preview` is not export-gated, verified live
// on a DRAFT: 200, a real PDF, both formats, while the download is still 403). Nothing asked
// it for one.
//
// These assert the preview is actually mounted on the review surface, because "the endpoint
// exists" is exactly the state this repo keeps mistaking for "the feature exists".
//
// The surface is the will DOCUMENT PAGE (/wills/:id/document) — the prototype's `willDoc`
// route, "Will export". It went through two wrong homes first: the last child of the will
// detail column (below the fold on every viewport), then the ~420px right-hand column of
// the review screen, directly under a Flutter-drawn mock of a will made of grey bars.
//
// Putting it on the review screen was a deliberate choice in this repo, argued in a comment
// that has since been deleted. The prototype overrides it: prototype lines 1685-1814 give
// the document its own centred 660px page and review step 6 shows no document at all. These
// tests are rewritten to follow that, rather than dropped.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show disclaimerProvider, willsApiProvider, willProvider, witnessesProvider, trusteesProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';
import 'package:wasiati/features/wills/presentation/will_document_screen.dart';
import 'package:wasiati/features/wills/presentation/will_preview_card.dart';

final _pdf = Uint8List.fromList(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
          '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
          '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>'
      .codeUnits,
);

class _Api extends WillsApi {
  _Api(this.step) : super(Dio());
  final int step;

  /// Every will id the screen asked to preview — proves it previews the will in hand.
  final List<String> previewed = [];

  Will get _d => Will(id: 'draft-1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': step,
        'sex': 'male',
        'wives': 1,
        'sons': 2,
        'madhhab': 'JUMHUR',
        'wishes': const {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
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
  @override
  Future<Uint8List> previewPdf(String willId,
      {String format = 'table', String lang = 'en', String display = 'percent'}) async {
    previewed.add(willId);
    return _pdf;
  }
}

Future<_Api> _open(WidgetTester t, {required int step}) async {
  final api = _Api(step);
  t.view.physicalSize = const Size(1200, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
      emailVerifiedProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: KeyedSubtree(key: ValueKey('step-$step'), child: const CreateWillScreen()),
    ),
  ));
  // Explicit pumps, NOT pumpAndSettle: the PDF viewer keeps a frame loop running, so
  // settling never completes once the preview is mounted (the toggle test hit this too).
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  return api;
}

/// The will document page — the one screen whose job is the document. Same stubbed API, so
/// `previewed` still records which will was actually fetched.
Future<_Api> _openReview(WidgetTester t) async {
  final api = _Api(6);
  t.view.physicalSize = const Size(1200, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      willProvider('draft-1').overrideWith((ref) => api.getOne('draft-1')),
      witnessesProvider('draft-1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('draft-1').overrideWith((ref) async => const <Trustee>[]),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
      emailVerifiedProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WillDocumentScreen(willId: 'draft-1'),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  return api;
}

void main() {
  testWidgets('the document page shows the document itself, not just a summary', (t) async {
    await _openReview(t);
    expect(find.byType(WillPreviewCard), findsOneWidget,
        reason: 'the document page must show the document');
    // The document now renders as LIVE native text by default — no PDF fetch, no soft
    // rasterised page — so what proves it is showing THIS will, without being asked, is the
    // document's own words on screen: the title, and this will's DRAFT state (it is unsealed).
    expect(find.text('Last Will & Testament'), findsOneWidget,
        reason: 'the live document itself must be on screen, not just a summary');
    expect(find.textContaining('Draft — not yet sealed'), findsOneWidget,
        reason: 'it must reflect THIS will — an unsealed draft — not a generic sealed sample');
  });

  testWidgets('the format toggles are usable before sealing', (t) async {
    await _openReview(t);
    // The same controls as the post-seal page: an owner deciding whether the wording reads
    // correctly needs the narrative form, which is the whole point of offering it.
    expect(find.text('Table'), findsOneWidget);
    expect(find.text('Narrative'), findsOneWidget);
    expect(find.text('Fraction'), findsOneWidget);
  });

  testWidgets('the guided wizard does NOT render it, on any step', (t) async {
    // It costs a headless-Chromium render per fetch, and a half-built will is not worth
    // reading — the preview belongs at the point of decision, which is now the review page.
    final api = await _open(t, step: 3);
    expect(find.byType(WillPreviewCard), findsNothing);
    expect(api.previewed, isEmpty);
  });
}
