import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/passkey_service.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/google_sign_in_service.dart';
import '../features/auth/domain/auth_state.dart';
import 'network/dio_client.dart';
import 'storage/token_store.dart';

/// In-memory access token + secure refresh storage.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// The configured Dio client. Session-expiry (refresh failure) is routed to the
/// AuthController lazily to avoid a construction cycle.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.create(
    tokenStore: ref.read(tokenStoreProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.read(apiClientProvider).dio));

/// WebAuthn passkey flows (sign-in + registration). Lives here beside
/// authApiProvider so AuthController can reach it without an import cycle.
final passkeyServiceProvider = Provider<PasskeyService>((ref) => PasskeyService(ref.read(authApiProvider)));

/// Google Sign-In. Holds no state worth keeping between calls, but a single instance keeps
/// the SDK's own account cache in one place so signOut() actually clears what the next
/// sign-in would otherwise silently reuse.
final googleSignInServiceProvider = Provider<GoogleSignInService>((ref) => GoogleSignInService());

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Fresh emailVerified from /users/me, re-asked on every mount (autoDispose).
///
/// The cached session user goes stale the moment the emailed link is clicked —
/// usually in ANOTHER tab — and the login/register payloads don't carry the
/// field at all. Screens that gate on it (sealing requires a confirmed email,
/// fdb4c3e) watch this instead of AuthUser.emailVerified.
final emailVerifiedProvider = FutureProvider.autoDispose<bool>(
    (ref) async => (await ref.read(authApiProvider).me()).emailVerified);
