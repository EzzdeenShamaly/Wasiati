// The offer banner must render every field the admin authored for it.
//
// Offers are created in the commerce console (POST /admin/commerce/offers) with a
// title, subtitle, BODY and BADGE, and the public catalog sends all four. The app's
// Offer model dropped `body` entirely and the banner rendered neither body nor badge —
// so an admin who filled in "LIMITED" and a paragraph of copy saw both fields silently
// do nothing, with no error anywhere to explain why.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/commerce/application/commerce_providers.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';
import 'package:wasiati/features/commerce/presentation/pricing_screen.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() =>
      const AuthSignedIn(AuthUser(id: 'u1', email: 'sara@wasiati.test', region: 'US', role: 'USER'));
}

const _plan = PricingPlan(
  id: 'p1',
  tier: 'STANDARD',
  region: 'US',
  currency: 'USD',
  unitAmount: 9900,
  interval: 'MONTH',
  displayName: 'Standard',
  sortOrder: 0,
  active: true,
  features: ['One sealed will'],
);

Future<void> pumpPricing(WidgetTester t, Offer offer) async {
  await t.binding.setSurfaceSize(const Size(1200, 1500));
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      catalogProvider('US').overrideWith(
          (ref) async => Catalog(region: 'US', currency: 'USD', offers: [offer], plans: const [_plan])),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PricingScreen(),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  test('Offer.fromJson keeps body and badge — the fields the catalog sends', () {
    final o = Offer.fromJson(const {
      'id': 'o1',
      'title': 'Ramadan offer',
      'subtitle': '25% off Premium',
      'body': 'Applies to your first year. Ends Laylat al-Qadr.',
      'badge': 'Limited',
      'ctaLabel': 'Apply code',
      'promoCode': 'RAMADAN25',
      'active': true,
    });
    expect(o.body, 'Applies to your first year. Ends Laylat al-Qadr.');
    expect(o.badge, 'Limited');
  });

  testWidgets('the banner shows the badge and the body the admin wrote', (t) async {
    await pumpPricing(
      t,
      const Offer(
        id: 'o1',
        title: 'Ramadan offer',
        subtitle: '25% off Premium',
        body: 'Applies to your first year. Ends Laylat al-Qadr.',
        badge: 'Limited',
        active: true,
      ),
    );

    expect(find.text('Ramadan offer'), findsOneWidget);
    expect(find.text('25% off Premium'), findsOneWidget);
    expect(find.text('Applies to your first year. Ends Laylat al-Qadr.'), findsOneWidget);
    expect(find.text('LIMITED'), findsOneWidget); // badge pill, uppercased
  });

  testWidgets('an offer with only a title renders no empty pill and no blank line', (t) async {
    await pumpPricing(t, const Offer(id: 'o2', title: 'Zakat season', active: true));

    expect(find.text('Zakat season'), findsOneWidget);
    // Nothing rendered for the absent fields — a stray empty pill would show as a
    // gold dot beside the title. (Text widgets only: the promo box's EditableText
    // legitimately holds an empty string.)
    expect(find.byWidgetPredicate((w) => w is Text && w.data == ''), findsNothing);
  });
}
