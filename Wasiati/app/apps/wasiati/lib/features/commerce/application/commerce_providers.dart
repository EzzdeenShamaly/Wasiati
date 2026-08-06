import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/commerce_api.dart';
import '../data/payments_api.dart';
import '../domain/commerce_models.dart';

final commerceApiProvider = Provider<CommerceApi>((ref) => CommerceApi(ref.read(apiClientProvider).dio));

final paymentsApiProvider = Provider<PaymentsApi>((ref) => PaymentsApi(ref.read(apiClientProvider).dio));

/// Backs the Manage billing page: plan + renewal, card, invoices — one round trip.
/// (Supersedes the old `subscriptionProvider`, which only ever fed the billing
/// dialog this page replaced; `GET /payments/subscription` remains for anything
/// that wants just the subscription.)
final billingProvider =
    FutureProvider.autoDispose<BillingOverview>((ref) => ref.read(paymentsApiProvider).billing());

/// The account-credit ledger shown under the referral balances — where each
/// figure came from and where it went.
final creditHistoryProvider =
    FutureProvider.autoDispose<List<CreditEntry>>((ref) => ref.read(paymentsApiProvider).creditHistory());

final catalogProvider =
    FutureProvider.autoDispose.family<Catalog, String>((ref, region) => ref.read(commerceApiProvider).catalog(region));

final adminPlansProvider =
    FutureProvider.autoDispose<List<PricingPlan>>((ref) => ref.read(commerceApiProvider).adminListPlans());

final adminPromotionsProvider =
    FutureProvider.autoDispose<List<Promotion>>((ref) => ref.read(commerceApiProvider).adminListPromotions());

final adminOffersProvider =
    FutureProvider.autoDispose<List<Offer>>((ref) => ref.read(commerceApiProvider).adminListOffers());
