import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/features/portal/application/portal_providers.dart';
import 'package:wasiati/features/portal/data/portal_api.dart';
import 'package:wasiati/features/portal/domain/portal_models.dart';
import 'package:wasiati/features/portal/presentation/portal_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The executed will must be downloadable from the portal.
///
/// GET /portal/will/pdf shipped server-side — built, guarded, audited — with NO client.
/// `grep -rn "pdf" lib/features/portal/` returned zero, so the single artifact heirs
/// exist to receive was the only thing they could not get, while the commit message said
/// it had shipped. That is this project's recurring failure: a route with no caller, and
/// a green suite over it.
///
/// So these assert the CALL, not the button. A test that only finds the label would pass
/// against a handler that does nothing — which is exactly the state being fixed.

class _FixedPortal extends PortalController {
  _FixedPortal(this._state);
  final PortalState _state;
  @override
  PortalState build() => _state;
}

/// Records what the screen asked for.
class _RecordingApi implements PortalApi {
  final calls = <String>[];
  Object? throwThis;

  @override
  Future<Uint8List> pdf(String token, {String format = 'table', String lang = 'en', String display = 'percent'}) async {
    calls.add('pdf:token=$token,lang=$lang,format=$format');
    if (throwThis != null) throw throwThis!;
    return Uint8List.fromList([37, 80, 68, 70]); // "%PDF"
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName} not stubbed');
}

const _me = PortalMe(role: PortalRole.heir, estateName: 'ahmed@example.com', claimStatus: ClaimStatus.released);

PortalState _released() => const PortalState(
      step: PortalStep.view,
      token: 'tok-123',
      me: _me,
      claim: PortalClaim(status: ClaimStatus.released),
      will: PortalWill(
        estateName: 'ahmed@example.com',
        personalMessage: 'For my children.',
        shariaShares: [],
        bequests: [],
      ),
    );

Future<_RecordingApi> _pump(WidgetTester t, {Locale locale = const Locale('en')}) async {
  t.view.physicalSize = const Size(700, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final api = _RecordingApi();
  await t.pumpWidget(ProviderScope(
    overrides: [
      portalControllerProvider.overrideWith(() => _FixedPortal(_released())),
      portalApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      locale: locale,
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PortalScreen(),
    ),
  ));
  await t.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('the released estate offers the will PDF', (t) async {
    await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.portalWillPdfDownload), findsOneWidget,
        reason: 'the executed will is the artifact heirs exist to receive');
  });

  testWidgets('tapping it CALLS the endpoint — not just renders a button', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.portalWillPdfDownload));
    await t.pump();

    expect(api.calls, isNotEmpty, reason: 'the control must reach GET /portal/will/pdf');
    expect(api.calls.single, contains('token=tok-123'),
        reason: 'the session token authenticates it — the route takes no will id');
  });

  testWidgets('an Arabic reader gets the Arabic document', (t) async {
    // A family reading the portal in Arabic should not be handed an English will.
    final api = await _pump(t, locale: const Locale('ar'));
    final l = await AppLocalizations.delegate.load(const Locale('ar'));

    await t.tap(find.text(l.portalWillPdfDownload));
    await t.pump();

    expect(api.calls.single, contains('lang=ar'));
  });

  testWidgets('a failure surfaces to the reader instead of failing silently', (t) async {
    final api = await _pump(t);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    api.throwThis = Exception('boom');

    await t.tap(find.text(l.portalWillPdfDownload));
    await t.pumpAndSettle();

    // A message must reach the reader, and the button must not stay stuck spinning.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

