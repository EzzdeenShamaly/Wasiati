import '../../../core/network/api_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/auth_api.dart';
import '../domain/auth_models.dart';
import '../domain/auth_state.dart';

/// Owns the session lifecycle: resume-on-boot, login/register/MFA, social, and
/// logout. Persists tokens through the TokenStore; the Dio interceptor handles
/// silent refresh. All UI gates on the exposed AuthState.
class AuthController extends Notifier<AuthState> {
  AuthApi get _api => ref.read(authApiProvider);

  @override
  AuthState build() {
    // Kick off a session probe; state starts as AuthInitial.
    Future.microtask(bootstrap);
    return const AuthInitial();
  }

  /// Attempt to resume a session. On mobile this needs a stored refresh token;
  /// on web the httpOnly cookie is probed by simply calling /users/me (the
  /// interceptor refreshes the access token if needed).
  Future<void> bootstrap() async {
    final tokenStore = ref.read(tokenStoreProvider);
    final resumable = await tokenStore.hasPersistedSession();
    if (!resumable) {
      state = const AuthSignedOut();
      return;
    }
    try {
      final user = await _api.me();
      state = AuthSignedIn(user);
    } catch (_) {
      await tokenStore.clear();
      state = const AuthSignedOut();
    }
  }

  Future<void> _apply(Authenticated auth) async {
    await ref.read(tokenStoreProvider).setTokens(
          accessToken: auth.accessToken,
          refreshToken: auth.refreshToken,
        );
    state = AuthSignedIn(auth.user);
  }

  Future<void> register({
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
  }) async {
    final res = await _api.register(
      email: email,
      password: password,
      region: region,
      phone: phone,
      addressLine1: addressLine1,
      addressCity: addressCity,
      addressCountry: addressCountry,
      addressLine2: addressLine2,
      addressArea: addressArea,
      addressPostalCode: addressPostalCode,
    );
    await _apply(res);
  }

  Future<void> login({required String email, required String password}) async {
    final res = await _api.login(email: email, password: password);
    switch (res) {
      case Authenticated a:
        await _apply(a);
      case MfaRequired m:
        state = AuthAwaitingMfa(m.userId, m.via, m.challengeToken);
    }
  }

  Future<void> verifyMfa(String code) async {
    final s = state;
    if (s is! AuthAwaitingMfa) return;
    await _apply(await _api.verifyMfa(userId: s.userId, code: code));
  }

  /// Asks for a fresh login code on the SAME challenge.
  ///
  /// Throws on failure rather than swallowing it, so the screen restarts its countdown only
  /// when a code genuinely went out. Telling someone a code is on its way when none was
  /// sent is worse than the dead button this replaces — they will sit and wait for it.
  ///
  /// An empty token means the backend issued none (an older build), so there is nothing to
  /// resend against: fail here rather than posting a request that can only 400.
  Future<void> resendMfa() async {
    final s = state;
    if (s is! AuthAwaitingMfa) return;
    if (s.challengeToken.isEmpty) {
      throw ApiException('We could not resend the code. Please sign in again.');
    }
    await _api.resendMfa(challengeToken: s.challengeToken);
  }

  Future<void> loginWithGoogle({required String idToken, String? region, String? addressCountry}) async {
    await _apply(await _api.loginWithGoogle(idToken: idToken, region: region, addressCountry: addressCountry));
  }

  Future<void> loginWithApple({required String identityToken, String? region}) async {
    await _apply(await _api.loginWithApple(identityToken: identityToken, region: region));
  }

  Future<void> loginWithMicrosoft({required String idToken, String? region}) async {
    await _apply(await _api.loginWithMicrosoft(idToken: idToken, region: region));
  }

  /// Passkey sign-in (WebAuthn). The ceremony — options, browser prompt, verify —
  /// lives in PasskeyService; this applies the resulting session. Never lands in
  /// [AuthAwaitingMfa]: a passkey carries its own possession proof, so it is the
  /// one login path exempt from the always-OTP rule. Browser-side outcomes
  /// surface as typed PasskeyExceptions for the screen to translate.
  Future<void> loginWithPasskey() async {
    await _apply(await ref.read(passkeyServiceProvider).signIn());
  }

  void cancelMfa() => state = const AuthSignedOut();

  Future<void> logout() async {
    final tokenStore = ref.read(tokenStoreProvider);
    try {
      await _api.logout(refreshToken: await tokenStore.getRefreshToken());
    } catch (_) {
      // best-effort; clear locally regardless
    }
    await tokenStore.clear();
    state = const AuthSignedOut();
  }

  /// Called by the Dio interceptor when refresh fails — force sign-out.
  Future<void> sessionExpired() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AuthSignedOut();
  }
}
