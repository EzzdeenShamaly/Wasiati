import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';

/// End-to-end against the live backend (:4000), mirroring auth_api_integration_test.
/// An account is registered, a reset code requested, the REAL code read back off the
/// handset, and the password reset — then the old password must fail and the new one must
/// challenge for a second factor. Client-side proof that /auth/password/forgot-code and
/// /reset-code are what the app actually reaches, not just that its buttons render.
///
/// This used to register a PHONELESS account and read the code out of Mailhog, asserting
/// via=email. That scenario no longer exists on this path: a phone is mandatory at signup,
/// so every email+password account has one and its codes go by SMS. The email channel is
/// still real — social sign-in creates accounts with no phone — but it can no longer be
/// reached by registering, so asserting it here would be testing a fiction.
///
/// Run this file ALONE — the backend throttles per-IP and a 429 hard-fails.
void main() {
  test('forgot-code -> SMS code -> reset-code -> old password dead, new one challenges', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:4000',
      headers: {'X-Client-Platform': 'ios'},
      contentType: Headers.jsonContentType,
    ));
    final api = AuthApi(dio);
    final email = 'flutter_reset_${DateTime.now().microsecondsSinceEpoch}@wasiati.test';
    const oldPassword = 'OriginalPass123';
    const newPassword = 'BrandNewPass456';

    try {
      await registerTestUser(dio, email: email, password: oldPassword);

      await api.forgotPasswordCode(email);

      // Read the code back off the handset. The account has a phone — signup requires one —
      // so the reset code is delivered by SMS, and the dev outbox is where a developer
      // reads it. Newest FIRST: taking the other end returns an expired code from an
      // earlier run and looks like a broken verifier.
      final code = await latestDevSmsCode(dio);

      await api.resetPasswordWithCode(email: email, code: code, newPassword: newPassword);

      // The old password must be dead...
      await expectLater(
        api.login(email: email, password: oldPassword),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      // ...and the new one accepted, surfacing as the mandatory second factor rather than a
      // session. Channel is SMS because the account has a verified-capable number on file.
      final result = await api.login(email: email, password: newPassword);
      expect(result, isA<MfaRequired>());
      expect((result as MfaRequired).via, OtpChannel.sms,
          reason: 'signup requires a phone, so the login code goes to the handset');
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    } on DioException catch (e) {
      // Mailhog itself unreachable — same "environment not running" condition.
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        markTestSkipped('Mailhog not running (${e.message}) — start it to run this test');
        return;
      }
      rethrow;
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
