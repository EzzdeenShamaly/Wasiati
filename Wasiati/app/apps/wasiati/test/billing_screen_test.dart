import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/commerce/application/commerce_providers.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';
import 'package:wasiati/features/commerce/presentation/billing_screen.dart';

/// The Manage billing page (spec §2): current plan + renewal, payment method with
/// a change-card action, invoices with PDF, cancel link.
///
/// The property that matters most here is HONEST DEGRADATION. Everything on this
/// page except the card is ours — we run our own billing cycle — so with no Stripe
/// keys it must still show the plan, the renewal and the invoices, and say plainly
/// that card management is off rather than render a button that can only fail.
Future<void> pump(WidgetTester t, BillingOverview overview) async {
  t.view.physicalSize = const Size(1200, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [billingProvider.overrideWith((ref) async => overview)],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BillingScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

Invoice invoice({
  String id = 'i1',
  int amountMinor = 3900,
  int creditAppliedMinor = 0,
  int? chargedMinor,
  String status = 'PAID',
}) =>
    Invoice(
      id: id,
      issuedAt: DateTime.utc(2026, 7, 1),
      description: 'Wasiati Premium (month)',
      amountMinor: amountMinor,
      currency: 'SAR',
      creditAppliedMinor: creditAppliedMinor,
      chargedMinor: chargedMinor ?? amountMinor - creditAppliedMinor,
      status: status,
    );

final subscribed = BillingOverview(
  tier: 'PREMIUM',
  status: 'ACTIVE',
  interval: 'MONTH',
  currentPeriodEnd: DateTime.utc(2026, 8, 1),
  planDisplayName: 'Premium',
  planUnitAmount: 3900,
  planCurrency: 'SAR',
  hasPaymentMethod: true,
  card: const PaymentCard(brand: 'mada', last4: '4417'),
  canChangeCard: true,
  invoices: [invoice()],
);

void main() {
  testWidgets('shows the plan, the renewal date and price, the card, and invoices', (t) async {
    await pump(t, subscribed);

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Renews 2026-08-01 · SAR 39.00'), findsOneWidget);
    expect(find.text('Mada •••• 4417'), findsOneWidget);
    expect(find.text('Change card'), findsOneWidget);
    // The invoice row: date, amount, status, PDF.
    expect(find.text('2026-07-01'), findsOneWidget);
    expect(find.text('SAR 39.00'), findsOneWidget);
    expect(find.text('PAID'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Cancel subscription'), findsOneWidget);
  });

  testWidgets('WITHOUT provider keys: our data still shows; the card action does not', (t) async {
    await pump(t, BillingOverview(
      tier: subscribed.tier,
      status: subscribed.status,
      interval: subscribed.interval,
      currentPeriodEnd: subscribed.currentPeriodEnd,
      planDisplayName: subscribed.planDisplayName,
      planUnitAmount: subscribed.planUnitAmount,
      planCurrency: subscribed.planCurrency,
      // A card IS stored — we just cannot describe it and cannot change it here.
      hasPaymentMethod: true,
      card: null,
      canChangeCard: false,
      invoices: [invoice()],
    ));

    // Everything of ours is still on the page, fully truthful.
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Renews 2026-08-01 · SAR 39.00'), findsOneWidget);
    expect(find.text('PAID'), findsOneWidget);
    // We say what we know ("a card is saved") and no more.
    expect(find.text('Card on file'), findsOneWidget);
    expect(find.text('Card management is unavailable on this environment.'), findsOneWidget);
    // …and never offer an action that cannot work.
    expect(find.text('Change card'), findsNothing);
  });

  testWidgets('a renewal with no live plan price still states the date, promising no number', (t) async {
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'ACTIVE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 8, 1),
      planDisplayName: 'Premium',
      // Plan pulled from the catalog by an admin: we have no price to quote.
      hasPaymentMethod: false,
      canChangeCard: false,
    ));
    expect(find.text('Renews 2026-08-01'), findsOneWidget);
    expect(find.text('No card saved'), findsOneWidget);
  });

  testWidgets('PAST_DUE says the payment failed — not "Renews" on a date already behind us', (t) async {
    // The server sends `status`, and the plan card never read it: a subscriber whose
    // renewal was DECLINED saw "Renews 2026-07-28 · SAR 39.00" — a promise about a charge
    // that had already failed, quoting a past date — on the one screen where they could
    // still update the card before the dunning cron gives up and cancels them.
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'PAST_DUE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 7, 28), // behind us: the renewal that failed
      planDisplayName: 'Premium',
      planUnitAmount: 3900,
      planCurrency: 'SAR',
      hasPaymentMethod: true,
      card: const PaymentCard(brand: 'mada', last4: '4417'),
      canChangeCard: true,
      invoices: const [],
    ));

    expect(find.text('Payment failed on 2026-07-28'), findsOneWidget);
    expect(find.textContaining('Renews'), findsNothing);
    // What happens next and what to do about it — with the fix right below the words.
    expect(find.textContaining('Update your card'), findsOneWidget);
    expect(find.text('Change card'), findsOneWidget);
  });

  testWidgets('a cancelling subscription says when access ends, and offers resume', (t) async {
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'ACTIVE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 8, 1),
      cancelAtPeriodEnd: true,
      planDisplayName: 'Premium',
      planUnitAmount: 3900,
      planCurrency: 'SAR',
      hasPaymentMethod: true,
      canChangeCard: false,
      invoices: const [],
    ));

    expect(find.text('Access ends 2026-08-01'), findsOneWidget);
    expect(find.textContaining('Cancelling at period end'), findsOneWidget);
    expect(find.text('Resume subscription'), findsOneWidget);
    expect(find.text('Cancel subscription'), findsNothing);
  });

  testWidgets('an invoice part-paid by credit says so, and shows what the CARD was charged', (t) async {
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'ACTIVE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 8, 1),
      planDisplayName: 'Premium',
      hasPaymentMethod: true,
      canChangeCard: false,
      // SAR 39 total, SAR 10 from credit → SAR 29 on the card.
      invoices: [invoice(amountMinor: 3900, creditAppliedMinor: 1000)],
    ));

    expect(find.text('SAR 29.00'), findsOneWidget);
    expect(find.text('SAR 10.00 paid from account credit'), findsOneWidget);
  });

  testWidgets('a refunded invoice stops claiming it was paid', (t) async {
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'ACTIVE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 8, 1),
      planDisplayName: 'Premium',
      canChangeCard: false,
      invoices: [invoice(status: 'REFUNDED')],
    ));

    expect(find.text('REFUNDED'), findsOneWidget);
    expect(find.text('PAID'), findsNothing);
  });

  testWidgets('no subscription: a real empty state, not a blank shell', (t) async {
    await pump(t, const BillingOverview());

    expect(find.text('You have no active subscription'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    // Nothing to cancel or change.
    expect(find.text('Cancel subscription'), findsNothing);
    expect(find.text('Change card'), findsNothing);
  });

  testWidgets('subscribed but no invoices yet: says so instead of showing an empty list', (t) async {
    await pump(t, BillingOverview(
      tier: 'PREMIUM',
      status: 'ACTIVE',
      interval: 'MONTH',
      currentPeriodEnd: DateTime.utc(2026, 8, 1),
      planDisplayName: 'Premium',
      canChangeCard: false,
      invoices: const [],
    ));
    expect(find.textContaining('No invoices yet'), findsOneWidget);
  });
}
