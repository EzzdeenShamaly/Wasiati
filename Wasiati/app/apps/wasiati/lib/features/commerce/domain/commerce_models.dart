// Mirrors the backend commerce catalog (pricing/promos/offers).

class PricingPlan {
  final String id;
  final String tier;
  final String region;
  final String currency;
  final int unitAmount; // minor units
  final String interval; // ONE_TIME | MONTH | YEAR
  final String displayName;
  final String? description;
  final List<String> features;
  final String? badge;
  final int sortOrder;
  final bool active;

  /// Whether this (tier, interval) may actually be BOUGHT — the backend's
  /// plan-rules speaking (Ultimate cannot be purchased one-time: its burial
  /// contributions are inherently recurring). The server refuses such a checkout
  /// regardless; this only lets the app avoid offering it in the first place.
  /// Defaults true so an older/!unknown payload never silently hides a plan.
  final bool purchasable;

  const PricingPlan({
    required this.id,
    required this.tier,
    required this.region,
    required this.currency,
    required this.unitAmount,
    required this.interval,
    required this.displayName,
    required this.features,
    required this.sortOrder,
    required this.active,
    this.description,
    this.badge,
    this.purchasable = true,
  });

  factory PricingPlan.fromJson(Map<String, dynamic> j) => PricingPlan(
        id: j['id'] as String,
        tier: j['tier'] as String,
        region: j['region'] as String,
        currency: j['currency'] as String,
        unitAmount: (j['unitAmount'] as num).toInt(),
        interval: j['interval'] as String,
        displayName: j['displayName'] as String,
        description: j['description'] as String?,
        features: ((j['features'] as List?) ?? const []).map((e) => e.toString()).toList(),
        badge: j['badge'] as String?,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
        purchasable: j['purchasable'] as bool? ?? true,
      );

  bool get isOneTime => interval == 'ONE_TIME';

  String get priceLabel => formatMoney(unitAmount, currency);
}

class Offer {
  final String id;
  final String title;
  final String? subtitle;

  /// Longer copy under the subtitle. Every field here is admin-authored in the
  /// commerce console specifically to appear on this banner — a field the banner
  /// does not render is an admin control that silently does nothing.
  final String? body;
  final String? badge;
  final String? ctaLabel;
  final String? promoCode; // linked promotion code, if any — what the CTA applies
  final bool active;

  const Offer({
    required this.id,
    required this.title,
    this.subtitle,
    this.body,
    this.badge,
    this.ctaLabel,
    this.promoCode,
    required this.active,
  });

  /// The CTA is only shown when there is a real code for it to apply.
  bool get hasAction => ctaLabel != null && (promoCode?.isNotEmpty ?? false);

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        body: j['body'] as String?,
        badge: j['badge'] as String?,
        ctaLabel: j['ctaLabel'] as String?,
        promoCode: j['promoCode'] as String?,
        active: j['active'] as bool? ?? true,
      );
}

class Catalog {
  final String region;
  // Display currency chosen by the backend from the visitor's region (US=USD,
  // CA=CAD, KSA=SAR, else USD). Present even when [plans] is empty.
  final String currency;
  final List<PricingPlan> plans;
  final List<Offer> offers;
  const Catalog({required this.region, required this.currency, required this.plans, required this.offers});

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        region: j['region'] as String,
        currency: (j['currency'] as String?) ?? 'USD',
        plans: ((j['plans'] as List?) ?? const [])
            .map((e) => PricingPlan.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        offers: ((j['offers'] as List?) ?? const [])
            .map((e) => Offer.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class Promotion {
  final String id;
  final String code;
  final String type; // PERCENT | AMOUNT
  final int value;
  final String? currency;
  final String? description;
  final bool active;
  final int timesRedeemed;

  /// Redemption cap. Null = unlimited. The backend refuses the code once
  /// [timesRedeemed] reaches it, so this is the "limit by number of sign-ups".
  final int? maxRedemptions;

  /// Server-enforced at checkout: PromotionsService.validate() refuses the code
  /// for any user with a prior Invoice, and applyToAmount always passes the
  /// userId. Editable from the admin console. Not part of [isLiveAt] — such a
  /// code IS live, just not for returning buyers.
  final bool firstTimeOnly;

  /// Live window. Null on either side = open-ended in that direction.
  final DateTime? startsAt;
  final DateTime? endsAt;

  const Promotion({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.active,
    required this.timesRedeemed,
    this.currency,
    this.description,
    this.maxRedemptions,
    this.firstTimeOnly = false,
    this.startsAt,
    this.endsAt,
  });

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        id: j['id'] as String,
        code: j['code'] as String,
        type: j['type'] as String,
        value: (j['value'] as num).toInt(),
        currency: j['currency'] as String?,
        description: j['description'] as String?,
        active: j['active'] as bool? ?? true,
        timesRedeemed: (j['timesRedeemed'] as num?)?.toInt() ?? 0,
        maxRedemptions: (j['maxRedemptions'] as num?)?.toInt(),
        firstTimeOnly: j['firstTimeOnly'] as bool? ?? false,
        startsAt: DateTime.tryParse(j['startsAt'] as String? ?? ''),
        endsAt: DateTime.tryParse(j['endsAt'] as String? ?? ''),
      );

  String get valueLabel => type == 'PERCENT' ? '$value% off' : '${formatMoney(value, currency ?? 'USD')} off';

  /// True once the cap is hit — the backend will already be rejecting it.
  bool get isExhausted => maxRedemptions != null && timesRedeemed >= maxRedemptions!;

  /// Mirrors the server's window check so admins see the same verdict the
  /// checkout does. Authority stays server-side (PromotionsService.validate).
  bool isExpiredAt(DateTime now) => endsAt != null && endsAt!.isBefore(now);
  bool isScheduledAt(DateTime now) => startsAt != null && startsAt!.isAfter(now);

  /// What's actually stopping this code from working right now, if anything.
  bool isLiveAt(DateTime now) => active && !isExhausted && !isExpiredAt(now) && !isScheduledAt(now);
}

class PromoValidation {
  final bool valid;
  final String? reason;
  final String? type;
  final int? value;
  final String? description;

  const PromoValidation({required this.valid, this.reason, this.type, this.value, this.description});

  factory PromoValidation.fromJson(Map<String, dynamic> j) => PromoValidation(
        valid: j['valid'] as bool? ?? false,
        reason: j['reason'] as String?,
        type: j['type'] as String?,
        value: (j['value'] as num?)?.toInt(),
        description: j['description'] as String?,
      );
}

// --- Manage billing (spec §2) ----------------------------------------------

/// One receipt. Ours, not the PSP's: we run our own billing cycle, so Stripe has
/// no invoice list to show — see backend InvoicesService.
class Invoice {
  final String id;
  final DateTime issuedAt;
  final String description;

  /// Total value, INCLUDING any part settled from account credit.
  final int amountMinor;
  final String currency;
  final int creditAppliedMinor;

  /// What the card was actually charged (total minus credit).
  final int chargedMinor;
  final String status; // PAID | REFUNDED

  const Invoice({
    required this.id,
    required this.issuedAt,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.creditAppliedMinor,
    required this.chargedMinor,
    required this.status,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'] as String,
        issuedAt: DateTime.parse(j['issuedAt'] as String),
        description: j['description'] as String,
        amountMinor: (j['amountMinor'] as num).toInt(),
        currency: j['currency'] as String,
        creditAppliedMinor: (j['creditAppliedMinor'] as num?)?.toInt() ?? 0,
        chargedMinor: (j['chargedMinor'] as num?)?.toInt() ?? (j['amountMinor'] as num).toInt(),
        status: j['status'] as String? ?? 'PAID',
      );

  bool get refunded => status == 'REFUNDED';
  bool get paidWithCredit => creditAppliedMinor > 0;

  /// The receipt shows what was CHARGED; the credit part is called out separately,
  /// so a fully-credit-covered invoice reads as such rather than as free.
  String get amountLabel => formatMoney(chargedMinor, currency);
}

/// The stored card, as much as we may show. Null when the provider cannot be
/// reached or has no keys — the page then says "card on file" rather than
/// inventing a card.
class PaymentCard {
  final String? brand;
  final String? last4;
  const PaymentCard({this.brand, this.last4});

  factory PaymentCard.fromJson(Map<String, dynamic> j) =>
      PaymentCard(brand: j['brand'] as String?, last4: j['last4'] as String?);

  /// e.g. "Mada •••• 4417". Null when there is not enough to say anything true.
  String? get label {
    if (last4 == null) return null;
    final b = brand == null || brand!.isEmpty
        ? ''
        : '${brand![0].toUpperCase()}${brand!.substring(1)} ';
    return '$b•••• $last4';
  }
}

/// Everything the Manage billing page shows, in one payload.
class BillingOverview {
  final String? tier;
  final String? status;
  final String? interval;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;

  /// The live catalog price for what they hold, for the renewal line.
  final int? planUnitAmount;
  final String? planCurrency;
  final String? planDisplayName;

  final bool hasPaymentMethod;
  final PaymentCard? card;

  /// False when the provider has no keys (or there is no subscription): the app
  /// must not offer a "Change card" action that can only fail.
  final bool canChangeCard;
  final List<Invoice> invoices;

  const BillingOverview({
    this.tier,
    this.status,
    this.interval,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.planUnitAmount,
    this.planCurrency,
    this.planDisplayName,
    this.hasPaymentMethod = false,
    this.card,
    this.canChangeCard = false,
    this.invoices = const [],
  });

  /// True when there is no subscription at all — the page shows a "no plan" state
  /// rather than an empty shell.
  bool get hasSubscription => tier != null;

  factory BillingOverview.fromJson(Map<String, dynamic> j) {
    final sub = (j['subscription'] as Map?)?.cast<String, dynamic>();
    final plan = (j['plan'] as Map?)?.cast<String, dynamic>();
    final card = (j['card'] as Map?)?.cast<String, dynamic>();
    final end = sub?['currentPeriodEnd'] as String?;
    return BillingOverview(
      tier: sub?['tier'] as String?,
      status: sub?['status'] as String?,
      interval: sub?['interval'] as String?,
      currentPeriodEnd: end == null ? null : DateTime.tryParse(end),
      cancelAtPeriodEnd: sub?['cancelAtPeriodEnd'] as bool? ?? false,
      planUnitAmount: (plan?['unitAmount'] as num?)?.toInt(),
      planCurrency: plan?['currency'] as String?,
      planDisplayName: plan?['displayName'] as String?,
      hasPaymentMethod: j['hasPaymentMethod'] as bool? ?? false,
      card: card == null ? null : PaymentCard.fromJson(card),
      canChangeCard: j['canChangeCard'] as bool? ?? false,
      invoices: ((j['invoices'] as List?) ?? const [])
          .map((e) => Invoice.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  /// "SAR 39.00" for the renewal line, or null when we have no live plan price.
  String? get planPriceLabel =>
      planUnitAmount == null || planCurrency == null ? null : formatMoney(planUnitAmount!, planCurrency!);
}

/// One row of the account-credit ledger (`GET /credits/history`): every grant
/// and every spend. [amountMinor] is signed — positive = credit granted,
/// negative = credit consumed. A future [maturesAt] means the money is earned
/// but still inside its hold window (not yet spendable).
class CreditEntry {
  final String id;
  final int amountMinor;
  final String currency;
  final String reason; // REFERRAL_REWARD | PURCHASE_APPLIED | MANUAL_ADJUSTMENT | REFUND
  final String? description;
  final DateTime? maturesAt;
  final DateTime? createdAt;

  const CreditEntry({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.reason,
    this.description,
    this.maturesAt,
    this.createdAt,
  });

  bool isHeldAt(DateTime now) => maturesAt != null && maturesAt!.isAfter(now);

  factory CreditEntry.fromJson(Map<String, dynamic> j) => CreditEntry(
        id: j['id'] as String,
        amountMinor: (j['amountMinor'] as num?)?.toInt() ?? 0,
        currency: (j['currency'] as String?) ?? 'USD',
        reason: (j['reason'] as String?) ?? '',
        description: j['description'] as String?,
        maturesAt: DateTime.tryParse(j['maturesAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      );
}

/// Formats minor units into a currency string. Gulf currencies show their code;
/// USD/CAD use the dollar sign.
String formatMoney(int minor, String currency) {
  final major = (minor / 100).toStringAsFixed(2);
  return switch (currency.toUpperCase()) {
    'SAR' => 'SAR $major',
    'QAR' => 'QAR $major',
    'CAD' => 'CA\$$major',
    _ => '\$$major',
  };
}
