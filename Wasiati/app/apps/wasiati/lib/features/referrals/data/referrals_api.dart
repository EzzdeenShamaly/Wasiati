import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/referral_models.dart';

class ReferralsApi {
  final Dio _dio;
  ReferralsApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ReferralSummary> summary() => _guard(() async {
        final res = await _dio.get('/referrals/me');
        return ReferralSummary.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Attaches this account to a referrer's code. The server rejects self-referral,
  /// a second code, and any code applied after the first purchase.
  Future<void> claim(String code) => _guard(() => _dio.post('/referrals/claim', data: {'code': code}));
}
