// The Review & seal page tells an owner why sealing will refuse them.
//
// Sealing requires a confirmed email. Without this banner the owner ticks the disclaimer,
// presses the gold button, gets a bare snackbar, and is left on a dead screen with no hint
// that the fix is an email they never opened.
//
// This used to be asserted against step 6 of the create wizard, which sealed inline. Sealing
// now happens only here (DECISIONS §0: guided steps -> a required Review page -> seal), so
// this is the one screen that has to carry the warning.
//
// The matching server-side half is that signing is now refused BEFORE the will is locked
// (wills.service.ts signByOwner). Checking only at the seal let an unverified owner sign,
// lock the will, and then be refused — holding a will they could neither edit nor seal.

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
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';
import 'package:wasiati/features/wills/presentation/widgets/verify_email_notice.dart';

class _Api extends WillsApi {
  _Api() : super(Dio());
  Will get _d => const Will(id: 'd1', tier: 'STANDARD', locked: false, status: 'DRAFT', draftState: {
        'step': 6,
        'sex': 'male',
        'wives': 1,
        'sons': 2,
        'madhhab': 'JUMHUR',
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

Future<void> _open(WidgetTester t, {required bool emailVerified}) async {
  t.view.physicalSize = const Size(1100, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(_Api()),
      willProvider('d1').overrideWith((ref) async => _Api()._d),
      witnessesProvider('d1').overrideWith((ref) async => const <Witness>[]),
      trusteesProvider('d1').overrideWith((ref) async => const <Trustee>[]),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
      emailVerifiedProvider.overrideWith((ref) async => emailVerified),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ReviewSealScreen(willId: 'd1'),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('an unconfirmed email is called out on the review page', (t) async {
    await _open(t, emailVerified: false);
    expect(find.byType(VerifyEmailNotice), findsOneWidget,
        reason: 'the page that seals must say why sealing will refuse');
  });

  testWidgets('the notice offers a way to fix it, not just a complaint', (t) async {
    await _open(t, emailVerified: false);
    // A banner with no route to resolution is only marginally better than the snackbar it
    // replaced — the CTA is the point.
    expect(
      find.descendant(of: find.byType(VerifyEmailNotice), matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );
  });

  testWidgets('a confirmed email shows nothing — no nagging', (t) async {
    await _open(t, emailVerified: true);
    expect(find.byType(VerifyEmailNotice), findsNothing);
  });
}
