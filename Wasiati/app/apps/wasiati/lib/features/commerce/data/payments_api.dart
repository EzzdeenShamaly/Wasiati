import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';

/// Payments (Stripe). Start a hosted checkout, read the subscription, manage
/// billing, and cancel/resume.
///
/// Stripe is the card processor only — our own subscription engine runs the
/// billing cycle (we do not use Stripe Billing, so there is no hosted Billing
/// Portal) — and the app IS the billing portal, driving these endpoints directly.
class PaymentsApi {
  final Dio _dio;
  PaymentsApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// NOTE: no `region`. The buyer is signed in, so the backend prices from their
  /// ACCOUNT region — sending one from here would be ignored anyway, and asking
  /// the client for it is what let a VPN change someone's currency.
  Future<String> checkout({
    required String tier,
    // Required once a tier has both monthly and annual plans — the backend refuses
    // to guess rather than charge the wrong price.
    String? interval,
    String? promoCode,
    required String successUrl,
    required String cancelUrl,
  }) =>
      _guard(() async {
        final res = await _dio.post('/payments/checkout', data: {
          'tier': tier,
          if (interval != null && interval.isNotEmpty) 'interval': interval,
          if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
          'successUrl': successUrl,
          'cancelUrl': cancelUrl,
        });
        return (res.data as Map)['checkoutUrl'] as String;
      });

  /// Everything the Manage billing page shows, in one call.
  Future<BillingOverview> billing() => _guard(() async {
        final res = await _dio.get('/payments/billing');
        return BillingOverview.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Starts the hosted "change card" flow (a SetupIntent — nothing is charged).
  /// Returns the URL to send the customer to; the stored card only changes once
  /// the provider confirms the new one, so abandoning this is safe.
  Future<String> changeCardUrl({required String successUrl, required String cancelUrl}) => _guard(() async {
        final res = await _dio.post('/payments/payment-method', data: {
          'successUrl': successUrl,
          'cancelUrl': cancelUrl,
        });
        return (res.data as Map)['setupUrl'] as String;
      });

  /// Invoice PDF bytes. Owner-scoped and needs the auth header, so it comes via
  /// Dio rather than a bare URL.
  Future<Uint8List> invoicePdf(String invoiceId) => _guard(() async {
        final res = await _dio.get<List<int>>(
          '/payments/invoices/$invoiceId/pdf',
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  Future<Map<String, dynamic>?> subscription() => _guard(() async {
        final res = await _dio.get('/payments/subscription');
        return res.data == null ? null : (res.data as Map).cast<String, dynamic>();
      });

  /// Schedules cancellation at period end — the user keeps what they paid for.
  /// Never blocked: a burial plan is prepayment, so cancelling simply stops its
  /// contributions and makes them refundable.
  Future<void> cancelSubscription() => _guard(() => _dio.post('/payments/subscription/cancel'));

  /// Undoes a scheduled cancellation.
  Future<void> resumeSubscription() => _guard(() => _dio.post('/payments/subscription/resume'));

  /// My account credit, in minor units. `balanceMinor` is what can be spent today;
  /// `heldMinor` is referral commission still inside its hold window. They are kept
  /// apart on purpose — summing them would promise money the user cannot yet use.
  Future<({String currency, int balanceMinor, int heldMinor})> credit() => _guard(() async {
        final res = await _dio.get('/credits/me');
        final m = (res.data as Map).cast<String, dynamic>();
        return (
          currency: m['currency'] as String,
          balanceMinor: (m['balanceMinor'] as num).toInt(),
          heldMinor: (m['heldMinor'] as num?)?.toInt() ?? 0,
        );
      });

  /// The full credit ledger, newest first — every grant and every spend, so the
  /// balance above is explainable rather than just a number.
  Future<List<CreditEntry>> creditHistory() => _guard(() async {
        final res = await _dio.get('/credits/history');
        return (res.data as List)
            .map((e) => CreditEntry.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });
}
