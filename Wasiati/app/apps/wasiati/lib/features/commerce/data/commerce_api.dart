import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';

/// Public catalog + admin management of pricing, promotions, and offers.
class CommerceApi {
  final Dio _dio;
  CommerceApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // --- public storefront ---
  // Pass a [region] to force one; omit it to let the backend localize by visitor IP
  // (Cloudflare geo -> US=USD, CA=CAD, Saudi=SAR, else USD). The response's `currency`
  // reflects whichever was chosen.
  Future<Catalog> catalog([String? region]) => _guard(() async {
        final res = await _dio.get('/pricing',
            queryParameters: {if (region != null) 'region': region});
        return Catalog.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PromoValidation> validatePromo({required String code, String? tier, String? region}) => _guard(() async {
        final res = await _dio.post('/pricing/validate-promo', data: {
          'code': code,
          if (tier != null) 'tier': tier,
          if (region != null) 'region': region,
        });
        return PromoValidation.fromJson((res.data as Map).cast<String, dynamic>());
      });

  // --- admin: pricing plans ---
  Future<List<PricingPlan>> adminListPlans() => _guard(() async {
        final res = await _dio.get('/admin/commerce/plans');
        return (res.data as List).map((e) => PricingPlan.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<void> adminUpdatePlan(String id, Map<String, dynamic> patch) =>
      _guard(() => _dio.patch('/admin/commerce/plans/$id', data: patch));

  // --- admin: promotions ---
  Future<List<Promotion>> adminListPromotions() => _guard(() async {
        final res = await _dio.get('/admin/commerce/promotions');
        return (res.data as List).map((e) => Promotion.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<void> adminCreatePromotion(Map<String, dynamic> data) =>
      _guard(() => _dio.post('/admin/commerce/promotions', data: data));

  /// PATCH semantics: an ABSENT field is left unchanged; an explicit null CLEARS
  /// it (remove the cap, open the date window). The backend distinguishes the two.
  Future<void> adminUpdatePromotion(String id, Map<String, dynamic> patch) =>
      _guard(() => _dio.patch('/admin/commerce/promotions/$id', data: patch));

  /// DELETE archives (active: false) — reversible via [adminReinstatePromotion],
  /// which restores the code with its redemption count intact.
  Future<void> adminDeletePromotion(String id) => _guard(() => _dio.delete('/admin/commerce/promotions/$id'));

  Future<void> adminReinstatePromotion(String id) =>
      _guard(() => _dio.post('/admin/commerce/promotions/$id/reinstate'));

  // --- admin: offers ---
  Future<List<Offer>> adminListOffers() => _guard(() async {
        final res = await _dio.get('/admin/commerce/offers');
        return (res.data as List).map((e) => Offer.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// PATCH semantics as for promotions: absent = unchanged. Toggling `active`
  /// is the everyday use; title/subtitle/badge/ctaLabel edits ride the same call.
  Future<void> adminUpdateOffer(String id, Map<String, dynamic> patch) =>
      _guard(() => _dio.patch('/admin/commerce/offers/$id', data: patch));

  /// Hard delete — unlike promotions there is no archive/reinstate for offers;
  /// the storefront card is simply gone.
  Future<void> adminDeleteOffer(String id) => _guard(() => _dio.delete('/admin/commerce/offers/$id'));
}
