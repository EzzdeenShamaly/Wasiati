import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class IdentityApi {
  final Dio _dio;
  IdentityApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<String> createSessionUrl() => _guard(() async {
        final res = await _dio.post('/identity/verification-session');
        return (res.data as Map)['url'] as String;
      });

  /// Status, plus whether a KYC vendor is configured at all. When `available` is
  /// false the backend returns 503 from createSessionUrl, so the UI must not
  /// offer a verify button that is guaranteed to fail.
  Future<IdentityStatus> status() => _guard(() async {
        final res = await _dio.get('/identity/status');
        final m = (res.data as Map).cast<String, dynamic>();
        return IdentityStatus(
          status: m['status'] as String,
          available: m['available'] as bool? ?? false,
        );
      });
}

class IdentityStatus {
  final String status; // UNVERIFIED | PENDING | VERIFIED | REJECTED
  final bool available; // false until a document-KYC vendor is wired up
  const IdentityStatus({required this.status, required this.available});
}
