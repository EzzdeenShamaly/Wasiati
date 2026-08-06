import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/identity/data/identity_api.dart';

/// A fresh user is UNVERIFIED. Skips if the backend is unreachable OR throttled
/// (429) — an ApiException from any call is treated as "can't run here", while a
/// genuine assertion mismatch (TestFailure) still fails.
void main() {
  test('new user identity status is UNVERIFIED', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000', headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    try {
      final reg = await registerTestUser(dio,
          email: 'kyc_${DateTime.now().microsecondsSinceEpoch}@wasiati.test', password: 'KycPass12345');
      dio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';
      // Inside the guard: a 429 here now skips instead of failing.
      //
      // Bound to the typed field, not the object. `status()` returned a bare String
      // until 92a65c6 wrapped it in IdentityStatus to carry `available`; `expect` takes
      // dynamic, so comparing the object to 'UNVERIFIED' still compiled and simply
      // never matched. It went unseen because this test only runs when the backend is
      // up — every other run skipped.
      //
      // The `String` annotation is the guard, not decoration. Reading `.status` alone
      // only catches a rename; re-typing the field (String -> enum) would still satisfy
      // expect()'s dynamic matcher and silently stop matching — the same bug, one shape
      // change later. Annotating makes that a compile error, which `flutter analyze`
      // catches without needing a backend to be reachable.
      final identity = await IdentityApi(dio).status();
      final String status = identity.status;
      expect(status, 'UNVERIFIED');
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 20)));
}
