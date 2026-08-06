// Every will can be deleted, draft included.
//
// The delete control was rendered under `if (isPrimary && sealed)`, following the prototype
// (5a) literally. So a DRAFT could never be removed from the account — which is the state an
// owner is in most often: an abandoned first attempt, a revision thought better of, a will
// started on the wrong madhhab. Worse, the one-published-plus-one-draft cap (spec §3) meant a
// stuck draft actively blocked starting a new one, with no way out of it in the UI.
//
// The backend never had this restriction: WillsService.remove() takes any status and only
// refuses on an active death claim. So this was a control the server supported and the app
// declined to offer — the same shape of gap as the export toggles and the will preview.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show willsApiProvider, willsListProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/wills_list_screen.dart';

class _Api extends WillsApi {
  _Api() : super(Dio());
  final List<String> deleted = [];
  String? codeRequestedFor;

  @override
  Future<String?> sendWillDeleteCode(String willId) async {
    codeRequestedFor = willId;
    return '123456';
  }

  @override
  Future<void> deleteWill(String willId, String otp) async => deleted.add(willId);
}

Will _will({required String id, required String status}) => Will(
      id: id,
      tier: 'STANDARD',
      locked: status != 'DRAFT',
      status: status,
      requiredWitnesses: 2,
      updatedAt: DateTime(2026, 5, 3),
      sealedAt: status == 'SEALED' ? DateTime(2026, 5, 3) : null,
    );

Future<_Api> _open(WidgetTester t, List<Will> wills) async {
  final api = _Api();
  t.view.physicalSize = const Size(1100, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      willsApiProvider.overrideWithValue(api),
      willsListProvider.overrideWith((ref) async => wills),
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

void main() {
  testWidgets('a DRAFT offers Delete — the case that was unreachable', (t) async {
    await _open(t, [_will(id: 'd1', status: 'DRAFT')]);
    expect(find.widgetWithText(OutlinedButton, 'Delete will'), findsOneWidget);
  });

  testWidgets('a SEALED will still offers Delete', (t) async {
    await _open(t, [_will(id: 's1', status: 'SEALED')]);
    expect(find.widgetWithText(OutlinedButton, 'Delete will'), findsOneWidget);
  });

  testWidgets('a SIGNED but unsealed will offers it too', (t) async {
    // Mid-lifecycle wills were equally stranded: signed, awaiting witnesses, undeletable.
    await _open(t, [_will(id: 'x1', status: 'SIGNED')]);
    expect(find.widgetWithText(OutlinedButton, 'Delete will'), findsOneWidget);
  });

  testWidgets('every will in a list gets its own control, not just the primary', (t) async {
    await _open(t, [
      _will(id: 's1', status: 'SEALED'),
      _will(id: 'd1', status: 'DRAFT'),
    ]);
    expect(find.widgetWithText(OutlinedButton, 'Delete will'), findsNWidgets(2));
  });

  testWidgets('the draft warning does not claim the will was sealed', (t) async {
    // The sealed copy names signatures and witnesses a draft does not have. A warning that
    // misdescribes what is being destroyed is one people learn to click past.
    await _open(t, [_will(id: 'd1', status: 'DRAFT')]);
    await t.tap(find.widgetWithText(OutlinedButton, 'Delete will'));
    await t.pumpAndSettle();
    expect(find.text('Delete this draft?'), findsOneWidget);
    expect(find.textContaining('sealed will'), findsNothing);
  });

  testWidgets('deleting a draft STILL demands the step-up code', (t) async {
    // Spec §3 requires re-authentication for delete with no exemption by status, and a draft
    // still holds the family's names and shares. Confirming intent must not be enough.
    final api = await _open(t, [_will(id: 'd1', status: 'DRAFT')]);
    await t.tap(find.widgetWithText(OutlinedButton, 'Delete will'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete will'));
    await t.pumpAndSettle();

    expect(api.codeRequestedFor, 'd1', reason: 'a code must be sent before anything is destroyed');
    expect(api.deleted, isEmpty, reason: 'nothing may be deleted until the code is entered');
  });
}
