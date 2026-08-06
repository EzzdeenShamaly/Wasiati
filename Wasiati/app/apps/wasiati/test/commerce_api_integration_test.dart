import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/commerce/data/commerce_api.dart';

/// Verifies the Flutter commerce client against the live backend catalog.
/// An ApiException from any call (backend down or 429 throttle) skips the test;
/// a genuine assertion mismatch (TestFailure) still fails — so `on ApiException`,
/// never a bare `catch (e)` that would swallow a real regression.
void main() {
  test('public catalog + promo validation against the live backend', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000', contentType: Headers.jsonContentType));
    final api = CommerceApi(dio);
    try {
      final cat = await api.catalog('US');
      expect(cat.plans, isNotEmpty, reason: 'seeded US plans should be present');
      expect(cat.plans.first.priceLabel, startsWith('\$'));

      final valid = await api.validatePromo(code: 'LAUNCH25', region: 'US');
      expect(valid.valid, isTrue);

      final invalid = await api.validatePromo(code: 'NOPE_NOT_REAL', region: 'US');
      expect(invalid.valid, isFalse);
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 20)));
}
