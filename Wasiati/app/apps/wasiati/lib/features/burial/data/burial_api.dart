import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/burial_models.dart';

class BurialApi {
  final Dio _dio;
  BurialApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<BurialEstimate> create({
    required String city,
    required double baseAmount,
    required String currency,
    double? inflationRatePercent,
    int? projectionYears,
  }) =>
      _guard(() async {
        final res = await _dio.post('/burial-estimates', data: {
          'city': city,
          'baseAmount': baseAmount,
          'currency': currency,
          if (inflationRatePercent != null) 'inflationRatePercent': inflationRatePercent,
          if (projectionYears != null) 'projectionYears': projectionYears,
        });
        return BurialEstimate.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<List<BurialEstimate>> list() => _guard(() async {
        final res = await _dio.get('/burial-estimates');
        return (res.data as List).map((e) => BurialEstimate.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<void> requestQuote(String id) => _guard(() => _dio.post('/burial-estimates/$id/request-quote'));

  // --- admin: the manual mosque-outreach queue ---

  Future<List<BurialQuoteRequest>> adminPendingQuotes() => _guard(() async {
        final res = await _dio.get('/admin/burial-estimates/pending');
        return (res.data as List)
            .map((e) => BurialQuoteRequest.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Records the manually-sourced quote; the backend flips the row to QUOTED and
  /// the client sees it on their Burial page.
  Future<void> adminSubmitQuote(String estimateId, {required double amount, String? notes}) =>
      _guard(() => _dio.post('/burial-estimates/$estimateId/manual-quote', data: {
            'amount': amount,
            if (notes != null && notes.isNotEmpty) 'notes': notes,
          }));
}
