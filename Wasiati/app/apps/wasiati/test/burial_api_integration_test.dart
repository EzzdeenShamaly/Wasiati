import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/burial/data/burial_api.dart';

/// Burial planning is Ultimate-gated. Admin (bypass) should get a projected
/// amount; a normal user should be blocked with 403. Skips if backend is down.
void main() {
  const base = 'http://localhost:4000';

  test('admin gets an inflation-projected estimate; normal user is 403-gated', () async {
    // Admin (entitlement bypass)
    final adminDio = Dio(BaseOptions(baseUrl: base, headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    final userDio = Dio(BaseOptions(baseUrl: base, headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    try {
      final res = await loginFully(adminDio, email: 'admin@wasiati.test', password: 'AdminPass12345');
      adminDio.options.headers['Authorization'] = 'Bearer ${res.accessToken}';

      final est = await BurialApi(adminDio).create(city: 'Toronto', baseAmount: 10000, currency: 'CAD', inflationRatePercent: 4, projectionYears: 10);
      expect(est.projectedAmount, greaterThan(est.baseAmount)); // inflation applied
      expect(est.currency, 'CAD');

      // Normal user (no Ultimate) => 403
      final reg = await registerTestUser(userDio,
          email: 'burial_${DateTime.now().microsecondsSinceEpoch}@wasiati.test', password: 'BurialPass12345');
      userDio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';

      await expectLater(
        BurialApi(userDio).create(city: 'Austin', baseAmount: 8000, currency: 'USD'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 25)));
}
