import 'package:dio/dio.dart';
import '../config/env.dart';

/// The header the backend's ClaimTokenGuard reads. Deliberately NOT
/// `Authorization: Bearer` — a claim/portal token and a JWT have very different
/// blast radii, and sharing a header invites a route (or a future global guard) to
/// accept whichever it finds. Mirrors CLAIM_TOKEN_HEADER in claim-token.guard.ts.
const claimTokenHeader = 'X-Claim-Token';

/// A bare Dio for the accountless claim + portal surfaces.
///
/// This exists SEPARATELY from [ApiClient] on purpose, and the reason is not tidiness:
///
///  * apiClientProvider's Dio carries AuthInterceptor, which attaches the signed-in
///    user's Bearer token to every request. A signed-in user may legitimately also be
///    an heir on someone else's will, so those calls would go out carrying a
///    credential the portal never asked for.
///  * Worse, AuthInterceptor treats a 401 as "my session died" and calls
///    onSessionExpired() (auth_interceptor.dart:42). An expired PORTAL token returns
///    401 — which would sign a real user out of their own Wasiati account because a
///    12-hour portal session they opened for a relative's estate lapsed.
///
/// So: no interceptors, no token store, no refresh. The only credential is the opaque
/// token passed per call, and a 401 means exactly one thing — this link is finished.
class PortalClient {
  final Dio dio;
  PortalClient._(this.dio);

  factory PortalClient.create() => PortalClient._(Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
      )));

  /// Per-request options carrying the opaque token. Kept as a helper so no caller
  /// hand-rolls the header name.
  static Options auth(String token) => Options(headers: {claimTokenHeader: token});
}
