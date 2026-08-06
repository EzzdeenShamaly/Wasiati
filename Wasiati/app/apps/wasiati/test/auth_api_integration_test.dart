import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';

/// Exercises the real backend at localhost:4000 (mobile mode → refresh token in
/// body). An ApiException from any call (backend down OR 429 throttle) skips the
/// test; a genuine assertion mismatch (TestFailure) still fails the run.
void main() {
  test('register -> authenticated /users/me against the live backend', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:4000',
      headers: {'X-Client-Platform': 'ios'},
      contentType: Headers.jsonContentType,
    ));
    final api = AuthApi(dio);
    final email = 'flutter_${DateTime.now().microsecondsSinceEpoch}@wasiati.test';

    try {
      final auth = await registerTestUser(dio, email: email, password: 'FlutterPass123');
      expect(auth.accessToken, isNotEmpty);
      expect(auth.refreshToken, isNotNull, reason: 'mobile mode returns the refresh token in the body');
      expect(auth.user.email, email);

      dio.options.headers['Authorization'] = 'Bearer ${auth.accessToken}';
      final me = await api.me();
      expect(me.email, email);
      expect(me.region, 'US');
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 25)));
}
