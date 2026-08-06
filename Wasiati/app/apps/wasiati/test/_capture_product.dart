import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:dio/dio.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show willsListProvider, disclaimerProvider, willProvider, witnessesProvider, trusteesProvider, willsApiProvider;
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';
import 'package:wasiati/features/wills/presentation/review_seal_screen.dart';
import 'package:wasiati/features/zakat/presentation/zakat_screen.dart';
import 'package:wasiati/features/zakat/application/zakat_providers.dart';
import 'package:wasiati/features/zakat/domain/zakat_models.dart';
import 'package:wasiati/features/referrals/presentation/referrals_screen.dart';
import 'package:wasiati/features/referrals/application/referrals_providers.dart';
import 'package:wasiati/features/referrals/domain/referral_models.dart';
import 'package:wasiati/features/identity/presentation/kyc_screen.dart';
import 'package:wasiati/features/identity/application/identity_providers.dart';
import 'package:wasiati/features/identity/data/identity_api.dart';
import 'package:wasiati/features/wills/presentation/will_start_screen.dart';
import 'package:wasiati/features/ai_intake/presentation/ai_intake_screen.dart';
import 'package:wasiati/features/ai_intake/application/ai_intake_providers.dart';
import 'package:wasiati/features/ai_intake/data/ai_intake_api.dart';
import 'package:wasiati/features/ai_intake/domain/ai_intake_models.dart';
import 'package:wasiati/features/admin/presentation/admin_users_screen.dart';
import 'package:wasiati/features/admin/application/admin_users_providers.dart';
import 'package:wasiati/features/admin/data/admin_users_api.dart';
import 'package:wasiati/features/content/presentation/admin_content_screen.dart';
import 'package:wasiati/features/content/application/content_providers.dart';
import 'package:wasiati/features/content/data/content_api.dart';
import 'package:wasiati/features/commerce/application/entitlement_providers.dart';
import 'package:wasiati/features/home/presentation/dashboard_screen.dart';
import 'package:wasiati/features/vault/application/vault_providers.dart';
import 'package:wasiati/features/vault/domain/vault_models.dart';
import 'package:wasiati/features/vault/presentation/vault_screen.dart';
import 'package:wasiati/features/wills/presentation/create_will_screen.dart';
import 'package:wasiati/features/wills/presentation/wills_list_screen.dart';
import 'package:wasiati/features/burial/application/burial_providers.dart';
import 'package:wasiati/features/burial/presentation/burial_screen.dart';
import 'package:wasiati/features/death_claims/application/death_claims_providers.dart';
import 'package:wasiati/features/death_claims/presentation/death_claims_admin_screen.dart';
import 'package:wasiati/features/legacy/presentation/legacy_messages_screen.dart';
import 'package:wasiati/features/assets/application/assets_providers.dart';
import 'package:wasiati/features/assets/domain/asset_models.dart';
import 'package:wasiati/features/assets/presentation/assets_screen.dart';
import 'package:wasiati/features/wills/presentation/sealed_screen.dart';
import 'package:wasiati/features/checkin/application/checkin_providers.dart';
import 'package:wasiati/features/settings/presentation/settings_screen.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';
import 'package:wasiati/features/commerce/application/commerce_providers.dart';
import 'package:wasiati/features/commerce/presentation/pricing_screen.dart';

// Product screens rendered to PNGs with mocked providers. Run:
//   flutter test --update-goldens test/_capture_product.dart
class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'ahmed@wasiati.test', region: 'US', role: 'ADMIN'));
}

/// Renders the intake happy-path without a backend: Ameen opens the conversation.
class _FakeIntakeApi implements AiIntakeApi {
  @override
  Future<IntakeTurn> start() async => const IntakeTurn(
        sessionId: 's1',
        reply:
            "As-salamu alaykum, Ahmed. I'm Ameen. I'll ask a few gentle questions and turn your answers into a Sharia-compliant will — you can review every line before anything is sealed. To begin: who are the people you'd like to provide for?",
        extracted: ExtractedData(),
        completed: false,
      );
  @override
  Future<IntakeTurn> message(String sessionId, String text) async =>
      const IntakeTurn(sessionId: 's1', reply: 'Noted.', extracted: ExtractedData(), completed: false);
  @override
  // finalize creates no will now — it hands back the seed the guided form starts from.
  Future<IntakeSeed> finalize(String sessionId) async => const IntakeSeed(sons: 1);
  @override
  Future<void> markSeeded(String sessionId, String willId) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The create-will flow autosaves to a server-created draft before it advances
/// past step 1, and the six-step flow restores a draft at its saved step. Offline
/// (goldens) that would stall, so we stub every call the flow makes: list()/getOne
/// (restore + status), create()/updateDraft() (autosave), and the sub-resource
/// getters (heir contacts, witnesses, trustees) the registry/people steps read.
/// [openAtStep] > 1 seeds a restorable draft so a capture opens straight on that
/// step without driving through the earlier ones.
class _FakeWillsApi extends WillsApi {
  final int openAtStep;
  _FakeWillsApi({this.openAtStep = 1}) : super(Dio());
  Will get _draft => Will(
        id: 'draft-1',
        tier: 'STANDARD',
        locked: false,
        status: 'DRAFT',
        draftState: {
          'step': openAtStep,
          'sex': 'male',
          'sons': 2,
          'daughters': 1,
          'madhhab': 'JUMHUR',
          'bequest': {'name': 'Local orphans fund', 'third': 60.0},
          'wishes': {'sunnah': true, 'simple': true, 'local': true, 'azaa': true},
          'words': '',
        },
      );
  @override
  Future<List<Will>> list() async => openAtStep > 1 ? [_draft] : const [];
  @override
  Future<Will> getOne(String id) async => _draft;
  @override
  Future<Will> create({required String tier, required List<Heir> heirs, String madhhab = 'JUMHUR'}) async => _draft;
  @override
  Future<Will> updateDraft(String willId, Map<String, dynamic> draftState) async => _draft;
  @override
  Future<List<HeirContact>> heirContacts(String willId) async => const [];
  @override
  Future<List<Witness>> witnesses(String willId) async => const [];
  @override
  Future<List<Trustee>> trustees(String willId) async => const [];
}

Future<void> _load(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final a in assets) {
    loader.addFont(rootBundle.load(a));
  }
  await loader.load();
}

Future<void> _fonts() async {
  await _load('Fraunces', ['assets/fonts/Fraunces.ttf']);
  await _load('Public Sans', ['assets/fonts/PublicSans.ttf']);
  await _load('Amiri', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']);
  await _load('IBM Plex Sans Arabic',
      ['assets/fonts/IBMPlexSansArabic-Regular.ttf', 'assets/fonts/IBMPlexSansArabic-Bold.ttf']);
  await _load('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
}

/// Some screens never go idle — a typing indicator, a looping progress animation — and
/// pumpAndSettle waits for idle forever. [settle] false pumps a bounded number of frames
/// instead, which is enough to lay a screen out for a golden.
Future<void> _pump(WidgetTester t, Widget screen, Size size, List<Override> overrides,
    {bool settle = true}) async {
  await _fonts();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    ),
  ));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets('dashboard', (t) async {
    await _pump(t, const DashboardScreen(), const Size(1100, 1400), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsListProvider.overrideWith((ref) async => <Will>[]),
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{'tier': 'STANDARD', 'active': true}),
      // The rebuilt dashboard also reads identity + vault + referral for the
      // checklist/stat tiles and the referral rail.
      identityStatusProvider.overrideWith((ref) async => const IdentityStatus(status: 'VERIFIED', available: true)),
      vaultListProvider.overrideWith((ref) async => <VaultItem>[]),
      referralSummaryProvider.overrideWith((ref) async => const ReferralSummary(
            code: 'AHMED-7Q2',
            shareUrl: 'https://wasiati.app/?ref=AHMED-7Q2',
            invited: 6,
            qualified: 3,
            rewarded: 3,
            capped: 0,
            currency: 'USD',
            earnedThisYearMinor: 9000,
            yearlyCapMinor: 30000,
            remainingThisYearMinor: 21000,
            creditSpendableMinor: 6000,
            creditHeldMinor: 3000,
            holdDays: 30,
            friendDiscountPercent: 30,
          )),
    ]);
    await expectLater(find.byType(DashboardScreen), matchesGoldenFile('cap_dashboard.png'));
  });

  testWidgets('vault', (t) async {
    await _pump(t, const VaultScreen(), const Size(1100, 1300), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{'tier': 'PREMIUM', 'active': true}),
      vaultListProvider.overrideWith((ref) async => <VaultItem>[]),
    ]);
    await expectLater(find.byType(VaultScreen), matchesGoldenFile('cap_vault.png'));
  });

  testWidgets('create_will', (t) async {
    await _pump(t, const CreateWillScreen(), const Size(1200, 1800), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'This is a religious tool, not legal advice.')),
    ]);
    // Expand the extended family so the golden shows uncles + cousins.
    await t.tap(find.textContaining('Add extended family'));
    await t.pumpAndSettle();
    await expectLater(find.byType(CreateWillScreen), matchesGoldenFile('cap_create_will.png'));
  });

  testWidgets('bequest', (t) async {
    // Restore straight onto step 4 (estate & bequest) via a seeded draft.
    await _pump(t, const CreateWillScreen(), const Size(1200, 1500), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsApiProvider.overrideWithValue(_FakeWillsApi(openAtStep: 4)),
      disclaimerProvider.overrideWith((ref) async => (version: 'v1', text: 'This is a religious tool, not legal advice.')),
    ]);
    await t.pumpAndSettle();
    await expectLater(find.byType(CreateWillScreen), matchesGoldenFile('cap_bequest.png'));
    // Step 5 — wishes & words. The field arrives PRE-FILLED with the classic wasiyya
    // (see wasiyya_preload_test.dart), so the golden shows the real template, not a hint.
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();
    await expectLater(find.byType(CreateWillScreen), matchesGoldenFile('cap_words.png'));
    expect(find.textContaining('In the name of Allah'), findsWidgets);
  });

  testWidgets('wills_list', (t) async {
    // One SEALED will with full meta (heirs, bequest, witnesses, dates) so the golden
    // exercises the prototype card: meta line + supersede line + second-will starter.
    final sealed = Will(
      id: 'w1',
      tier: 'STANDARD',
      locked: true,
      status: 'SEALED',
      sealedAt: DateTime(2026, 5, 3),
      updatedAt: DateTime(2026, 5, 3),
      requiredWitnesses: 2,
      shariaShares: const [
        ShariaShare(heirRelation: 'WIFE', heirName: 'Zainab', sharePercent: 12.5),
        ShariaShare(heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 58.3),
        ShariaShare(heirRelation: 'DAUGHTER', heirName: 'Maryam', sharePercent: 14.6),
        ShariaShare(heirRelation: 'DAUGHTER', heirName: 'Aisha', sharePercent: 14.6),
      ],
      bequests: const [Bequest(id: 'b1', beneficiaryName: 'Local masjid', sharePercent: 6)],
      witnesses: const [
        Witness(id: 'wt1', fullName: 'Khalid', phone: '', status: 'SIGNED'),
        Witness(id: 'wt2', fullName: 'Omar', phone: '', status: 'SIGNED'),
      ],
    );
    await _pump(t, const WillsListScreen(), const Size(1100, 1000), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsListProvider.overrideWith((ref) async => [sealed]),
    ]);
    await expectLater(find.byType(WillsListScreen), matchesGoldenFile('cap_wills_list.png'));
  });

  testWidgets('burial', (t) async {
    await _pump(t, const BurialScreen(), const Size(1100, 1400), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{'tier': 'ULTIMATE', 'active': true}),
      burialListProvider.overrideWith((ref) async => []),
    ]);
    await expectLater(find.byType(BurialScreen), matchesGoldenFile('cap_burial.png'));
  });

  testWidgets('pricing', (t) async {
    const catalog = Catalog(region: 'US', currency: 'USD', offers: [], plans: [
      PricingPlan(id: 'p1', tier: 'BASIC', region: 'US', currency: 'USD', unitAmount: 27900, interval: 'ONE_TIME', displayName: 'Basic', sortOrder: 0, active: true, description: 'A complete will, once.', features: ['One sealed will', "Fara'id shares computed live", 'Witnesses & a trustee']),
      PricingPlan(id: 'p2', tier: 'PREMIUM', region: 'US', currency: 'USD', unitAmount: 9900, interval: 'MONTH', displayName: 'Premium', sortOrder: 1, active: true, badge: 'MOST POPULAR', description: 'The full legacy toolkit.', features: ['Everything in Basic', 'Encrypted vault', 'AI intake (Ameen)', 'Video messages']),
      PricingPlan(id: 'p3', tier: 'ULTIMATE', region: 'US', currency: 'USD', unitAmount: 19900, interval: 'MONTH', displayName: 'Ultimate', sortOrder: 2, active: true, description: 'Everything, plus burial.', features: ['Everything in Premium', 'Burial contributions', 'Priority support']),
      PricingPlan(id: 'p4', tier: 'PREMIUM', region: 'US', currency: 'USD', unitAmount: 99000, interval: 'YEAR', displayName: 'Premium', sortOrder: 1, active: true, badge: 'MOST POPULAR', description: 'The full legacy toolkit.', features: ['Everything in Basic', 'Encrypted vault', 'AI intake (Ameen)', 'Video messages']),
      PricingPlan(id: 'p5', tier: 'ULTIMATE', region: 'US', currency: 'USD', unitAmount: 199000, interval: 'YEAR', displayName: 'Ultimate', sortOrder: 2, active: true, description: 'Everything, plus burial.', features: ['Everything in Premium', 'Burial contributions', 'Priority support']),
    ]);
    await _pump(t, const PricingScreen(), const Size(1200, 1500), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      catalogProvider('US').overrideWith((ref) async => catalog),
    ]);
    await expectLater(find.byType(PricingScreen), matchesGoldenFile('cap_pricing.png'));
  });

  testWidgets('settings', (t) async {
    await _pump(t, const SettingsScreen(), const Size(1100, 1500), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      checkinStatusProvider.overrideWith((ref) async => throw 'mock'),
    ]);
    await expectLater(find.byType(SettingsScreen), matchesGoldenFile('cap_settings.png'));
  });

  testWidgets('legacy', (t) async {
    await _pump(t, const LegacyMessagesScreen(), const Size(1100, 1200), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{'tier': 'PREMIUM', 'active': true}),
      willsListProvider.overrideWith((ref) async => []),
    ]);
    await expectLater(find.byType(LegacyMessagesScreen), matchesGoldenFile('cap_legacy.png'));
  });

  testWidgets('assets', (t) async {
    await _pump(t, const AssetsScreen(willId: 'w1'), const Size(1200, 1500), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      assetsProvider('w1').overrideWith((ref) async => const [
            EstateAsset(
                id: 'a1',
                label: 'Current account',
                kind: 'BANK',
                estimatedValue: 184000,
                currency: 'USD',
                institution: 'First National',
                contactPhone: '+1 800 124 1222',
                contactEmail: 'care@firstnational.com',
                accountRef: 'US03 8000 0000 6080 1016 7519'),
            EstateAsset(
                id: 'a2',
                label: 'Family home',
                kind: 'REAL_ESTATE',
                estimatedValue: 620000,
                currency: 'USD',
                institution: 'County registry',
                accountRef: 'Deed 2284'),
            EstateAsset(
                id: 'a3',
                label: 'Brokerage portfolio',
                kind: 'SHARES',
                estimatedValue: 96400,
                currency: 'USD',
                institution: 'Fidelity',
                contactEmail: 'care@fidelity.com'),
            EstateAsset(
                id: 'l1',
                label: 'Home mortgage',
                kind: 'LIABILITY',
                estimatedValue: 210000,
                currency: 'USD',
                institution: 'First National',
                contactPhone: '+1 800 124 1222'),
            EstateAsset(id: 'l2', label: 'Car loan', kind: 'LIABILITY', estimatedValue: 24000, currency: 'USD', institution: 'AutoBank'),
          ]),
      // The zakat estimate banner at the bottom of the inventory.
      zakatEstimateProvider.overrideWith((ref) async => const ZakatEstimate(
            currency: 'USD',
            categories: [],
            excludedCryptoMinor: 0,
            unconverted: [],
            zakatableTotalMinor: 28040000,
            nisabMinor: 650000,
            aboveNisab: true,
            zakatDueMinor: 701000,
            hawl: Hawl(12, 9),
            charityUrl: null,
          )),
    ]);
    await expectLater(find.byType(AssetsScreen), matchesGoldenFile('cap_assets.png'));
    // Open the inline "Add to the inventory" panel (prototype 9a) and capture it.
    await t.tap(find.text('Add asset'));
    await t.pumpAndSettle();
    await expectLater(find.byType(AssetsScreen), matchesGoldenFile('cap_assets_add.png'));
  });

  testWidgets('sealed', (t) async {
    await _pump(t, const SealedScreen(willId: 'w1'), const Size(1100, 1000), [
      authControllerProvider.overrideWith(_FakeAuth.new),
    ]);
    await expectLater(find.byType(SealedScreen), matchesGoldenFile('cap_sealed.png'));
  });

  testWidgets('death_claims', (t) async {
    await _pump(t, const DeathClaimsAdminScreen(), const Size(1100, 1100), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      pendingClaimsProvider.overrideWith((ref) async => []),
    ]);
    await expectLater(find.byType(DeathClaimsAdminScreen), matchesGoldenFile('cap_death_claims.png'));
  });

  const will = Will(
    id: 'w1',
    tier: 'PREMIUM',
    locked: false,
    status: 'SIGNED',
    disclaimerVersion: 'v1',
    personalMessage: 'To my children — hold to your prayers, be gentle with your mother, and keep the ties of kinship. I love you. — Baba',
    shariaShares: [
      ShariaShare(heirRelation: 'WIFE', heirName: 'Layla', sharePercent: 12.5),
      ShariaShare(heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 43.75),
      ShariaShare(heirRelation: 'DAUGHTER', heirName: 'Maryam', sharePercent: 21.875),
      ShariaShare(heirRelation: 'DAUGHTER', heirName: 'Aisha', sharePercent: 21.875),
    ],
    bequests: [
      Bequest(id: 'b1', beneficiaryName: 'Local masjid', sharePercent: 10, notes: 'For the new wudu facilities'),
      Bequest(id: 'b2', beneficiaryName: 'Orphan sponsorship', sharePercent: 5),
    ],
  );

  testWidgets('will_detail', (t) async {
    await _pump(t, const WillDetailScreen(willId: 'w1'), const Size(1200, 1700), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willProvider('w1').overrideWith((ref) async => will),
      witnessesProvider('w1').overrideWith((ref) async => const [
            Witness(id: 'x1', fullName: 'Ibrahim Haddad', phone: '+1 555 0100', status: 'CONFIRMED'),
            Witness(id: 'x2', fullName: 'Sara Nasser', phone: '+1 555 0101', status: 'PENDING'),
          ]),
      trusteesProvider('w1').overrideWith((ref) async => const [
            Trustee(id: 'tr1', fullName: 'Omar Farouq', phone: '+1 555 0200', status: 'CONFIRMED'),
          ]),
    ]);
    await expectLater(find.byType(WillDetailScreen), matchesGoldenFile('cap_will_detail.png'));
  });

  testWidgets('review_seal', (t) async {
    await _pump(t, const ReviewSealScreen(willId: 'w1'), const Size(1100, 1200), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willProvider('w1').overrideWith((ref) async => will),
      witnessesProvider('w1').overrideWith((ref) async => const [
            Witness(id: 'x1', fullName: 'Ibrahim Haddad', phone: '+1 555 0100', status: 'CONFIRMED'),
            Witness(id: 'x2', fullName: 'Sara Nasser', phone: '+1 555 0101', status: 'CONFIRMED'),
          ]),
      trusteesProvider('w1').overrideWith((ref) async => const [
            Trustee(id: 'tr1', fullName: 'Omar Farouq', phone: '+1 555 0200', status: 'CONFIRMED'),
          ]),
    ]);
    await expectLater(find.byType(ReviewSealScreen), matchesGoldenFile('cap_review_seal.png'));
  });

  testWidgets('zakat', (t) async {
    await _pump(t, const ZakatScreen(), const Size(1100, 1300), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      zakatEstimateProvider.overrideWith((ref) async => const ZakatEstimate(
            currency: 'USD',
            categories: [
              ZakatCategory(type: 'CASH', totalMinor: 4200000, basisKey: 'zakat.basis.cash'),
              ZakatCategory(type: 'BANK_ACCOUNT', totalMinor: 3150000, basisKey: 'zakat.basis.bank'),
              ZakatCategory(type: 'GOLD', totalMinor: 1875000, basisKey: 'zakat.basis.gold'),
            ],
            excludedCryptoMinor: 0,
            unconverted: [],
            zakatableTotalMinor: 9225000,
            nisabMinor: 650000,
            aboveNisab: true,
            zakatDueMinor: 230625,
            hawl: Hawl(15, 9),
            charityUrl: 'https://example.org/give',
          )),
    ]);
    await expectLater(find.byType(ZakatScreen), matchesGoldenFile('cap_zakat.png'));
  });

  testWidgets('referrals', (t) async {
    await _pump(t, const ReferralsScreen(), const Size(1100, 1200), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      referralSummaryProvider.overrideWith((ref) async => const ReferralSummary(
            code: 'AHMED-7Q2',
            shareUrl: 'https://wasiati.app/?ref=AHMED-7Q2',
            invited: 6,
            qualified: 3,
            rewarded: 3,
            capped: 0,
            currency: 'USD',
            earnedThisYearMinor: 9000,
            yearlyCapMinor: 30000,
            remainingThisYearMinor: 21000,
            creditSpendableMinor: 6000,
            creditHeldMinor: 3000,
            holdDays: 30,
            friendDiscountPercent: 30,
          )),
    ]);
    await expectLater(find.byType(ReferralsScreen), matchesGoldenFile('cap_referrals.png'));
  });

  testWidgets('kyc', (t) async {
    await _pump(t, const KycScreen(), const Size(1100, 1000), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      identityStatusProvider.overrideWith((ref) async => const IdentityStatus(status: 'UNVERIFIED', available: true)),
    ]);
    await expectLater(find.byType(KycScreen), matchesGoldenFile('cap_kyc.png'));
  });

  testWidgets('will_start', (t) async {
    await _pump(t, const WillStartScreen(), const Size(1100, 1000), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      entitlementProvider.overrideWith((ref) async => <String, dynamic>{
            'tier': 'PREMIUM',
            'active': true,
            'features': {'aiIntake': true, 'videoMessages': true},
          }),
    ]);
    await expectLater(find.byType(WillStartScreen), matchesGoldenFile('cap_will_start.png'));
  });

  testWidgets('ai_intake', (t) async {
    // settle: false — Ameen's conversation view keeps an animation running, so waiting for
    // idle never returns. This capture timed out for exactly that reason.
    await _pump(t, const AiIntakeScreen(), const Size(1100, 1200), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      aiIntakeApiProvider.overrideWithValue(_FakeIntakeApi()),
    ], settle: false);
    await expectLater(find.byType(AiIntakeScreen), matchesGoldenFile('cap_ai_intake.png'));
  });

  testWidgets('admin_users', (t) async {
    await _pump(t, const AdminUsersScreen(), const Size(1300, 1100), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      adminUsersProvider.overrideWith((ref) async => const AdminUsersData(
            total: 3,
            users: [
              AdminUser(id: 'u-ahmed', email: 'ahmed@wasiati.test', region: 'US', role: 'USER', idVerificationStatus: 'VERIFIED', emailVerified: true, createdAt: '2026-05-02T10:00:00Z', phone: '+1 555 0100', compTier: null, plan: 'STANDARD', lastIp: '203.0.113.4'),
              AdminUser(id: 'u-layla', email: 'layla@wasiati.test', region: 'KSA', role: 'USER', idVerificationStatus: 'PENDING', emailVerified: true, createdAt: '2026-06-11T09:30:00Z', phone: '+966 5 0000', compTier: 'PREMIUM', plan: 'PREMIUM', lastIp: '198.51.100.9'),
              AdminUser(id: 'u-omar', email: 'omar@wasiati.test', region: 'CA', role: 'ADMIN', idVerificationStatus: 'UNVERIFIED', emailVerified: false, createdAt: '2026-07-01T14:20:00Z', phone: null, compTier: null, plan: null, lastIp: null),
            ],
            byRegion: {'US': 1, 'KSA': 1, 'CA': 1},
            byStatus: {'VERIFIED': 1, 'PENDING': 1, 'UNVERIFIED': 1},
            byRole: {'USER': 2, 'ADMIN': 1},
            sealedWills: 7,
            sealedWillsWeek: 2,
          )),
    ]);
    await expectLater(find.byType(AdminUsersScreen), matchesGoldenFile('cap_admin_users.png'));
  });

  testWidgets('admin_content', (t) async {
    await _pump(t, const AdminContentScreen(), const Size(1300, 1000), [
      authControllerProvider.overrideWith(_FakeAuth.new),
      contentListProvider.overrideWith((ref) async => [
            ContentString(key: 'lndHeroTitle', valueEn: 'A will your family can trust', valueAr: 'وصية تطمئن لها عائلتك', note: 'Landing hero', published: true, updatedBy: 'admin', updatedAt: DateTime.utc(2026, 6, 1)),
            const ContentString(key: 'prPlansFor', valueEn: 'Plans for {region}', valueAr: 'الباقات في {region}', note: null, published: false, updatedBy: null, updatedAt: null),
          ]),
    ]);
    await expectLater(find.byType(AdminContentScreen), matchesGoldenFile('cap_admin_content.png'));
  });
}
