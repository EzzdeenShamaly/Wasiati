// The plan card must tell the truth about what the account actually has.
//
// The server's /entitlements/me sends `tier: null` for a FREE account and a `features`
// map saying exactly which perks the tier includes. The dashboard dropped both:
// `data['tier'] ?? 'STANDARD'` relabelled precisely the account the paywall applies to
// as a paying one — in the header chip AND the cream plan card — and the first two perks
// were hard-coded `Icons.check`, so a free (or one-time Basic) account was shown
// "Encrypted vault" and "Unlimited will edits" as included while every tap on them
// 403'd. The same file's own sibling helper (entitlementHas) existed to read the
// features map; this card was the path that never called it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/commerce/application/entitlement_providers.dart';
import 'package:wasiati/features/home/presentation/dashboard_screen.dart';
import 'package:wasiati/features/identity/application/identity_providers.dart';
import 'package:wasiati/features/identity/data/identity_api.dart';
import 'package:wasiati/features/referrals/application/referrals_providers.dart';
import 'package:wasiati/features/referrals/domain/referral_models.dart';
import 'package:wasiati/features/vault/application/vault_providers.dart';
import 'package:wasiati/features/vault/domain/vault_models.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() =>
      const AuthSignedIn(AuthUser(id: 'u1', email: 'sara@wasiati.test', region: 'US', role: 'USER'));
}

/// What the backend actually sends: featuresForTier in entitlements.service.ts.
Map<String, dynamic> entitlement(String? tier) => <String, dynamic>{
      'tier': tier,
      'source': tier == null ? 'none' : 'subscription',
      'isAdmin': false,
      'features': <String, dynamic>{
        'immutableWill': tier != null,
        'unlimitedEdits': tier == 'STANDARD' || tier == 'PREMIUM' || tier == 'ULTIMATE',
        'vault': tier == 'STANDARD' || tier == 'PREMIUM' || tier == 'ULTIMATE',
        'videoMessages': tier == 'PREMIUM' || tier == 'ULTIMATE',
      },
    };

Future<void> pumpDashboard(WidgetTester t, Map<String, dynamic> ent) async {
  await t.binding.setSurfaceSize(const Size(1100, 1400));
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsListProvider.overrideWith((ref) async => <Will>[]),
      entitlementProvider.overrideWith((ref) async => ent),
      identityStatusProvider.overrideWith((ref) async => const IdentityStatus(status: 'UNVERIFIED', available: true)),
      vaultListProvider.overrideWith((ref) async => <VaultItem>[]),
      referralSummaryProvider.overrideWith((ref) async => const ReferralSummary(
            code: 'SARA-1A1',
            shareUrl: 'https://wasiati.app/?ref=SARA-1A1',
            invited: 0,
            qualified: 0,
            rewarded: 0,
            capped: 0,
            currency: 'USD',
            earnedThisYearMinor: 0,
            yearlyCapMinor: 30000,
            remainingThisYearMinor: 30000,
            creditSpendableMinor: 0,
            creditHeldMinor: 0,
            holdDays: 30,
            friendDiscountPercent: 30,
          )),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DashboardScreen(),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a FREE account is called Free, and the paid perks show locked', (t) async {
    await pumpDashboard(t, entitlement(null));

    // Named honestly, and not once as "Standard" anywhere on the screen.
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Standard'), findsNothing);

    // The perk rows exist but carry locks, not ticks: vault + edits + video are all
    // features this account does not have. (Icons.check still appears elsewhere on the
    // dashboard, so count locks — three locked perks — rather than asserting no ticks.)
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));

    // And the call to action is to choose a plan, not to "upgrade" a plan they lack.
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Upgrade to Premium'), findsNothing);
  });

  testWidgets('a STANDARD account keeps its ticks — vault and edits are real there', (t) async {
    await pumpDashboard(t, entitlement('STANDARD'));

    expect(find.text('Standard'), findsWidgets);
    // Only video is locked at Standard.
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(1));
    expect(find.text('Upgrade to Premium'), findsOneWidget);
  });

  testWidgets('a PREMIUM account shows everything unlocked and no upsell', (t) async {
    await pumpDashboard(t, entitlement('PREMIUM'));

    expect(find.text('Premium'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Upgrade to Premium'), findsNothing);
    expect(find.text('See plans'), findsNothing);
  });
}
