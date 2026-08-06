import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/auth_models.dart';

/// Typed wrapper over the backend auth endpoints. Converts Dio failures into
/// ApiException so the UI gets clean, user-facing messages.
class AuthApi {
  final Dio _dio;
  AuthApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  AuthResult _parse(Response res) {
    final data = res.data as Map<String, dynamic>;
    if (data['mfaRequired'] == true) {
      return MfaRequired(
        data['userId'] as String,
        OtpChannel.parse(data['via']),
        // Absent from an older backend: fall back to empty, which the screen reads as
        // "resend unavailable" rather than firing a call that would 400.
        (data['challengeToken'] as String?) ?? '',
      );
    }
    return Authenticated(
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String?,
    );
  }

  /// Page 1 of signup. Phone and a structured postal address are REQUIRED by the server:
  /// the phone carries the login second factor, the witness and trustee invitations and the
  /// death-claim lookup, and the address decides jurisdiction and is printed into the
  /// executed will. Which address fields are mandatory depends on [addressCountry] — a
  /// postal code is required in the US and Canada and does not exist in Qatar — so the
  /// server validates and returns the offending field names in `fields`.
  Future<Authenticated> register({
    required String email,
    required String password,
    required String region,
    required String phone,
    required String addressLine1,
    required String addressCity,
    required String addressCountry,
    String? addressLine2,
    String? addressArea,
    String? addressPostalCode,
  }) =>
      _guard(() async {
        final res = await _dio.post('/auth/register', data: {
          'email': email,
          'password': password,
          'region': region,
          'phone': phone,
          'addressLine1': addressLine1,
          'addressCity': addressCity,
          'addressCountry': addressCountry,
          if (addressLine2 != null && addressLine2.isNotEmpty) 'addressLine2': addressLine2,
          if (addressArea != null && addressArea.isNotEmpty) 'addressArea': addressArea,
          if (addressPostalCode != null && addressPostalCode.isNotEmpty) 'addressPostalCode': addressPostalCode,
        });
        return _parse(res) as Authenticated;
      });

  Future<AuthResult> login({required String email, required String password}) =>
      _guard(() async => _parse(await _dio.post('/auth/login', data: {'email': email, 'password': password})));

  Future<Authenticated> verifyMfa({required String userId, required String code}) => _guard(() async {
        final res = await _dio.post('/auth/login/verify-mfa', data: {'userId': userId, 'code': code});
        return _parse(res) as Authenticated;
      });

  /// Re-sends the login code for an in-flight challenge.
  ///
  /// Takes the opaque challengeToken and NOTHING else — deliberately not the userId, which
  /// could be guessed into a stranger's challenge and used to pump SMS at their phone. The
  /// server answers `{ sent: true }` and never names the destination, so there is nothing
  /// useful to return; a throw is the only signal that no code went out.
  Future<void> resendMfa({required String challengeToken}) => _guard(() async {
        await _dio.post('/auth/login/resend-mfa', data: {'challengeToken': challengeToken});
      });

  /// Sends the signup code to the phone ALREADY on the account.
  ///
  /// Nothing names a destination — the session decides whose number to text. An endpoint
  /// that texted an arbitrary number on a valid session would be a free SMS gateway.
  Future<void> sendPhoneCode() => _guard(() async {
        await _dio.post('/auth/phone/send-code');
      });

  /// Confirms the signup code and marks the phone verified.
  Future<void> verifyPhone(String code) => _guard(() async {
        await _dio.post('/auth/phone/verify', data: {'code': code});
      });

  // --- authenticator app (TOTP) --------------------------------------------
  //
  // The free second factor. An enrolled app means no code is ever sent, which is both
  // cheaper (a Saudi SMS costs 15.6x a US one, and MFA fires on every password login)
  // and stronger — NIST SP 800-63B treats SMS as a restricted authenticator because of
  // SIM swap, an attack whose likeliest perpetrator here is a relative.

  Future<bool> totpEnabled() => _guard(() async {
        final res = await _dio.get('/auth/mfa/totp');
        return (res.data as Map)['enabled'] == true;
      });

  /// Begins enrolment. Returns the secret to display plus the `otpauth://` URI to encode
  /// as a QR code. Enables NOTHING — the account is unchanged until [totpEnable].
  Future<({String secret, String otpauthUri})> totpStart() => _guard(() async {
        final m = (await _dio.post('/auth/mfa/totp/start')).data as Map;
        return (secret: m['secret'] as String, otpauthUri: m['otpauthUri'] as String);
      });

  /// Confirms a code from the app, proving the secret was transferred intact, and only
  /// then switches the authenticator on.
  Future<void> totpEnable({required String secret, required String code}) => _guard(() async {
        await _dio.post('/auth/mfa/totp/enable', data: {'secret': secret, 'code': code});
      });

  /// Turns it off. Requires a current code: dropping your own second factor is the first
  /// thing an attacker holding a live session would do.
  Future<void> totpDisable(String code) => _guard(() async {
        await _dio.post('/auth/mfa/totp/disable', data: {'code': code});
      });

  // --- recovery codes -------------------------------------------------------

  /// How many backup codes remain. `low` is the server's own threshold — running out
  /// unnoticed is the lockout these exist to prevent.
  Future<({int remaining, int total, bool low})> recoveryCodesStatus() => _guard(() async {
        final m = (await _dio.get('/auth/mfa/recovery-codes')).data as Map;
        return (remaining: (m['remaining'] as num).toInt(), total: (m['total'] as num).toInt(), low: m['low'] == true);
      });

  /// Issues a fresh set and INVALIDATES the previous one. The plaintext comes back exactly
  /// once — there is nowhere to look these up again, which is what makes a stolen database
  /// useless for bypassing MFA, and why the UI has to insist the user saves them now.
  Future<List<String>> regenerateRecoveryCodes() => _guard(() async {
        final m = (await _dio.post('/auth/mfa/recovery-codes')).data as Map;
        return ((m['codes'] as List?) ?? const []).map((c) => c as String).toList();
      });

  /// The client obtains [idToken] from the google_sign_in SDK; the backend verifies it.
  /// [addressCountry] is sent on SIGNUP so the backend derives residency from where the
  /// user says they live, exactly as the password path does. `region` is the older, weaker
  /// input — the build's own region — and region is immutable, so getting it from the
  /// country matters. Harmless for a returning user: the server only reads it when it is
  /// creating the account.
  Future<Authenticated> loginWithGoogle({required String idToken, String? region, String? addressCountry}) =>
      _guard(() async {
        final res = await _dio.post('/auth/login/google', data: {
          'idToken': idToken,
          if (region != null) 'region': region,
          if (addressCountry != null && addressCountry.isNotEmpty) 'addressCountry': addressCountry,
        });
        return _parse(res) as Authenticated;
      });

  Future<Authenticated> loginWithApple({required String identityToken, String? region}) => _guard(() async {
        final res = await _dio.post('/auth/login/apple', data: {
          'identityToken': identityToken,
          if (region != null) 'region': region,
        });
        return _parse(res) as Authenticated;
      });

  /// The client obtains [idToken] from Microsoft's MSAL SDK; the backend verifies it.
  Future<Authenticated> loginWithMicrosoft({required String idToken, String? region}) => _guard(() async {
        final res = await _dio.post('/auth/login/microsoft', data: {
          'idToken': idToken,
          if (region != null) 'region': region,
        });
        return _parse(res) as Authenticated;
      });

  Future<void> logout({String? refreshToken}) =>
      _guard(() => _dio.post('/auth/logout', data: {if (refreshToken != null) 'refreshToken': refreshToken}));

  Future<AuthUser> me() =>
      _guard(() async => AuthUser.fromJson((await _dio.get('/users/me')).data as Map<String, dynamic>));

  // Passkeys (WebAuthn). Both options endpoints return `{ options, sessionId }`:
  // the server generates the challenge and keeps it in Redis keyed by the opaque
  // sessionId (single-use, 5 min TTL) — verify must echo that sessionId back
  // alongside the browser's response. The challenge itself is never trusted from
  // the client.

  /// Registration options for the signed-in user (JWT-guarded).
  Future<({String sessionId, Map<String, dynamic> options})> passkeyRegisterOptions() =>
      _guard(() async => _ceremonyOptions(await _dio.post('/auth/passkeys/register/options')));

  Future<void> passkeyRegisterVerify({
    required String sessionId,
    required Map<String, dynamic> response,
  }) =>
      _guard(() => _dio
          .post('/auth/passkeys/register/verify', data: {'sessionId': sessionId, 'response': response}));

  /// Sign-in options — public by design: the whole point is that no session exists yet.
  Future<({String sessionId, Map<String, dynamic> options})> passkeyLoginOptions() =>
      _guard(() async => _ceremonyOptions(await _dio.post('/auth/passkeys/login/options')));

  /// Exchanges the browser's assertion for a session. Never `MfaRequired`: a
  /// passkey carries its own possession proof, so it is the one login path
  /// exempt from the always-OTP rule.
  Future<Authenticated> passkeyLoginVerify({
    required String sessionId,
    required Map<String, dynamic> response,
  }) =>
      _guard(() async {
        final res = await _dio
            .post('/auth/passkeys/login/verify', data: {'sessionId': sessionId, 'response': response});
        return _parse(res) as Authenticated;
      });

  ({String sessionId, Map<String, dynamic> options}) _ceremonyOptions(Response res) {
    final data = res.data as Map<String, dynamic>;
    return (
      sessionId: data['sessionId'] as String,
      options: data['options'] as Map<String, dynamic>,
    );
  }

  // Email verification & password reset
  Future<void> verifyEmail(String token) => _guard(() => _dio.post('/auth/verify-email', data: {'token': token}));
  Future<void> resendVerification(String email) =>
      _guard(() => _dio.post('/auth/resend-verification', data: {'email': email}));
  Future<void> forgotPassword(String email) =>
      _guard(() => _dio.post('/auth/password/forgot', data: {'email': email}));
  Future<void> resetPassword({required String token, required String newPassword}) =>
      _guard(() => _dio.post('/auth/password/reset', data: {'token': token, 'newPassword': newPassword}));

  // Password reset by one-time CODE — the preferred path (151714a). The emailed
  // link above stays only for mail already sitting in inboxes.

  /// Requests a reset code. It goes to the account's phone when there is one,
  /// otherwise its email — and the response NEVER says which (or whether the
  /// account exists at all), so don't write copy that pretends to know.
  Future<void> forgotPasswordCode(String email) =>
      _guard(() => _dio.post('/auth/password/forgot-code', data: {'email': email}));

  /// Trades the code for a new password and revokes every session. All failures
  /// answer identically on purpose (unknown address, OAuth-only account,
  /// wrong/expired/burned code) — the UI must not try to tell them apart.
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _guard(() => _dio.post('/auth/password/reset-code',
          data: {'email': email, 'code': code, 'newPassword': newPassword}));
}
