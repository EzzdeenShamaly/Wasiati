import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/checkin/application/checkin_providers.dart';
import 'package:wasiati/features/checkin/data/checkin_api.dart';
import 'package:wasiati/features/referrals/application/referrals_providers.dart';
import 'package:wasiati/features/referrals/domain/referral_models.dart';
import 'package:wasiati/features/referrals/presentation/referrals_screen.dart';
import 'package:wasiati/features/settings/presentation/settings_screen.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart';
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// /referrals was registered but nothing navigated to it, and a SEALED will's
/// "Reopen to edit" button only ever showed a snackbar — so account credit and
/// will revision were both unreachable. Following signup_reachable_test.dart,
/// these tests assert the new entry points ACTUALLY NAVIGATE / ACTUALLY CALL
/// the endpoint, not merely render.
class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

const _summary = ReferralSummary(
  code: 'WAS-TEST1',
  shareUrl: 'https://wasiati.com/?ref=WAS-TEST1',
  invited: 0,
  qualified: 0,
  rewarded: 0,
  capped: 0,
  currency: 'USD',
  earnedThisYearMinor: 0,
  yearlyCapMinor: 100000,
  remainingThisYearMinor: 100000,
  creditSpendableMinor: 0,
  creditHeldMinor: 0,
  holdDays: 100,
  friendDiscountPercent: 10,
);

class _RecordingWillsApi extends WillsApi {
  _RecordingWillsApi() : super(Dio());
  final revised = <String>[];

  @override
  Future<Will> revise(String willId) async {
    revised.add(willId);
    return const Will(id: 'w2', tier: 'STANDARD', locked: false, status: 'DRAFT');
  }
}

const _sealed = Will(id: 'w1', tier: 'STANDARD', locked: true, status: 'SEALED');
const _sealedBasic = Will(id: 'w1', tier: 'BASIC', locked: true, status: 'SEALED');
const _draft = Will(id: 'w2', tier: 'STANDARD', locked: false, status: 'DRAFT');

void main() {
  testWidgets('settings: the referrals row actually lands on the referrals screen', (t) async {
    t.view.physicalSize = const Size(1000, 2600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuth(const AuthSignedIn(
            AuthUser(id: 'u1', email: 'a@b.com', role: 'USER', region: 'US')))),
        checkinStatusProvider.overrideWith((ref) async => const CheckinStatus(
            enabled: false,
            frequency: 'QUARTERLY',
            lastConfirmedAt: null,
            remindersSent: 0,
            trusteeAlerted: false,
            claimInitPolicy: 'BOTH')),
        referralSummaryProvider.overrideWith((ref) async => _summary),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(initialLocation: '/settings', routes: [
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/referrals', builder: (_, __) => const ReferralsScreen()),
        ]),
      ),
    ));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await t.ensureVisible(find.text(l.settingsReferrals));
    await t.pumpAndSettle();
    // Presence is not enough — the row must genuinely navigate.
    await t.tap(find.text(l.settingsReferrals));
    await t.pumpAndSettle();

    expect(find.byType(ReferralsScreen), findsOneWidget,
        reason: '/referrals is registered; without this row (and the dashboard rail '
            'link) nothing in the app ever navigated to it.');
  });

  Future<_RecordingWillsApi> pumpDetail(WidgetTester t, Will will) async {
    t.view.physicalSize = const Size(1200, 1800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final api = _RecordingWillsApi();
    await t.pumpWidget(ProviderScope(
      overrides: [
        willsApiProvider.overrideWithValue(api),
        willProvider.overrideWith((ref, id) async => id == 'w2' ? _draft : will),
        willsListProvider.overrideWith((ref) async => [will]),
        witnessesProvider.overrideWith((ref, id) async => const <Witness>[]),
        trusteesProvider.overrideWith((ref, id) async => const <Trustee>[]),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(initialLocation: '/wills/w1', routes: [
          GoRoute(
              path: '/wills/:id',
              builder: (_, s) => WillDetailScreen(willId: s.pathParameters['id']!)),
          GoRoute(path: '/wills', builder: (_, __) => const Scaffold()),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    return api;
  }

  testWidgets('sealed will: Reopen to edit calls /revise and lands on the new draft', (t) async {
    final api = await pumpDetail(t, _sealed);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.wdReopenToEdit));
    await t.pumpAndSettle();

    expect(api.revised, ['w1'],
        reason: 'The button used to be a dead snackbar; it must hit POST /wills/:id/revise.');
    expect(find.text(l.wdReviewSeal), findsOneWidget,
        reason: 'After revising, the owner should be ON the fresh draft (its header '
            'offers Review & seal), not still parked on the sealed will.');
  });

  testWidgets('sealed BASIC will: immutable — explains itself, does not call /revise', (t) async {
    final api = await pumpDetail(t, _sealedBasic);
    final l = await AppLocalizations.delegate.load(const Locale('en'));

    await t.tap(find.text(l.wdReopenToEdit));
    await t.pumpAndSettle();

    expect(api.revised, isEmpty);
    expect(find.text(l.wdReopenSnack), findsOneWidget);
  });
}
