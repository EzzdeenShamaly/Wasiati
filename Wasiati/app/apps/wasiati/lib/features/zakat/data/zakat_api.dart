import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/zakat_models.dart';

class ZakatApi {
  final Dio _dio;
  ZakatApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// 503 when no current gold price is configured — the niṣāb would be a guess.
  Future<ZakatEstimate> estimate() => _guard(() async {
        final res = await _dio.get('/zakat/estimate');
        return ZakatEstimate.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Hijri day (1–30) and month (1–12). The server rejects anything else.
  Future<void> setHawl({required int day, required int month}) =>
      _guard(() => _dio.put('/zakat/hawl', data: {'day': day, 'month': month}));
}
