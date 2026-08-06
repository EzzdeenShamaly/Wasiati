import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

/// Creates a will against the live backend and checks the Sharia shares.
/// An ApiException from any call (backend down or 429 throttle) skips the test.
void main() {
  test('create will computes Sharia shares (spouse+son+daughter)', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:4000',
      headers: {'X-Client-Platform': 'ios'},
      contentType: Headers.jsonContentType,
    ));
    final email = 'will_${DateTime.now().microsecondsSinceEpoch}@wasiati.test';
    try {
      final reg = await registerTestUser(dio, email: email, password: 'WillPass12345');
      dio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';

      final will = await WillsApi(dio).create(tier: 'STANDARD', heirs: const [
        Heir(HeirRelation.wife, 'Aisha'),
        Heir(HeirRelation.son, 'Yusuf'),
        Heir(HeirRelation.daughter, 'Maryam'),
      ]);

      expect(will.shariaShares, isNotEmpty);
      final wife = will.shariaShares.firstWhere((s) => s.heirRelation == 'WIFE');
      expect(wife.sharePercent, closeTo(12.5, 0.01)); // 1/8 with children
      final total = will.shariaShares.fold<double>(0, (a, s) => a + s.sharePercent);
      expect(total, closeTo(100, 0.5)); // children split the residue
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 25)));
}
