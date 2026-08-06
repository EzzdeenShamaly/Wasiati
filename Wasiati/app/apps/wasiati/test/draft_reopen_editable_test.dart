// Reopening a draft lands you in the guided steps, editable, with the progress bar.
//
// The owner: "draft opens in the review page I can't move to step 1 or any step behind it"
// and "will doesn't show step progress bar". One trap, three symptoms.
//
// Two things combined to close it. First, nothing routed a draft into the wizard at all:
// Continue on the dashboard and a tap on the wills list both went to /wills/:id, the will
// DETAIL page, whose only forward action for a draft is Review & seal. Second, the wizard
// itself redirected any draft stored on step 6 straight to Review — and handing off to
// Review is exactly what writes step 6, so every returning draft matched. That redirect
// used go(), which replaces the stack, so Review had nothing to pop and its back fell
// through to the will detail, whose only forward action is Review again.
//
// Net effect: steps 1-5 were unreachable from any will you came back to, the will could
// not be edited, and the only bar you ever saw was Review's, already complete.
//
// The wizard also could not have opened a specific draft even if something had asked it
// to: _restore() took `wills.where(isFlowDraft).firstOrNull`, a coin toss on an account
// with two drafts.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:wasiati/features/wills/presentation/widgets/will_step_bar.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@wasiati.test', region: 'US', role: 'USER'));
}

/// Two drafts on the account, deliberately. `wanted` is the one the owner picked; `other`
/// comes back FIRST from list(), so restoring by "first flow draft" opens the wrong will.
class _Api extends WillsApi {
  _Api({required this.wantedStep}) : super(Dio());
  final int wantedStep;

  Will _draft(String id, int step, int sons) => Will(
        id: id,
        tier: 'STANDARD',
        locked: false,
        status: 'DRAFT',
        draftState: {
          'step': step,
          'sex': 'male',
          'wives': 1,
          'sons': sons,
          'madhhab': 'JUMHUR',
          'wishes': const {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
          'words': '',
        },
      );

  Will get other => _draft('other-draft', 2, 4);
  Will get wanted => _draft('wanted-draft', wantedStep, 2);

  @override
  Future<List<Will>> list() async => [other, wanted];
  @override
  Future<Will> getOne(String id) async => id == 'wanted-draft' ? wanted : other;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => wanted;
  @override
  Future<Will> updateDraft(String w, Map<String, dynamic> s) async => wanted;
  @override
  Future<List<HeirContact>> heirContacts(String w) async => const [];
  @override
  Future<List<Witness>> witnesses(String w) async => const [];
  @override
  Future<List<Trustee>> trustees(String w) async => const [];
}

String? landedAt;

Future<void> _openEdit(WidgetTester t, {required int step}) async {
  landedAt = null;
  t.view.physicalSize = const Size(1400, 1100);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final router = GoRouter(
    initialLocation: '/wills/wanted-draft/edit',
    routes: [
      GoRoute(
        path: '/wills/:id/edit',
        builder: (_, s) => CreateWillScreen(willId: s.pathParameters['id']!),
      ),
      for (final p in const ['/wills', '/wills/:id/review', '/wills/:id'])
        GoRoute(
          path: p,
          builder: (_, s) {
            landedAt = s.matchedLocation;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
    ],
  );
  addTearDown(router.dispose);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsApiProvider.overrideWithValue(_Api(wantedStep: step)),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'Not legal advice.')),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pumpAndSettle();
}

int _filledSegments(WidgetTester t) {
  final bar = find.byType(WillStepBar);
  expect(bar, findsOneWidget, reason: 'the guided steps must show the progress bar');
  return t
      .widgetList<Container>(find.descendant(of: bar, matching: find.byType(Container)))
      .where((c) => (c.decoration as BoxDecoration?)?.color == WasiatiColors.brassGold)
      .length;
}

void main() {
  testWidgets('a draft saved on step 6 opens on step 5 — NOT bounced to review', (t) async {
    await _openEdit(t, step: 6);

    expect(landedAt, isNull,
        reason: 'opening a draft must not redirect anywhere — it landed on $landedAt');
    expect(find.byType(CreateWillScreen), findsOneWidget);
    expect(find.textContaining('Step 5 of 6'), findsWidgets,
        reason: 'step 6 is the review page; the wizard owns up to 5');
  });

  testWidgets('and the progress bar is there, at 5 of 6', (t) async {
    await _openEdit(t, step: 6);
    expect(_filledSegments(t), 5);
  });

  testWidgets('every earlier step is reachable — Back walks 5 down to 1', (t) async {
    // The complaint in one test: "I can't move to step 1 or any step behind it".
    await _openEdit(t, step: 6);
    for (var expected = 4; expected >= 1; expected--) {
      await t.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await t.pumpAndSettle();
      expect(find.textContaining('Step $expected of 6'), findsWidgets,
          reason: 'Back from step ${expected + 1} must reach step $expected');
      expect(_filledSegments(t), expected, reason: 'the bar must track the step it is on');
      expect(landedAt, isNull, reason: 'walking back must stay inside the wizard');
    }
  });

  testWidgets('opens the draft the owner PICKED, not whichever came back first', (t) async {
    // list() returns other-draft first, on step 2 with 4 sons; wanted-draft has 2 sons.
    // Restoring by "first flow draft" would open the wrong will and silently edit it.
    await _openEdit(t, step: 3);
    expect(find.textContaining('Step 3 of 6'), findsWidgets,
        reason: 'the picked draft is on step 3; the other one is on step 2');
  });
}
