import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/env.dart';

/// Holds the short-lived access token in memory only (never persisted to disk),
/// and the long-lived refresh token in platform secure storage on mobile.
/// On web the refresh token lives in an httpOnly cookie the app can't read, so
/// this store only tracks the access token there.
class TokenStore {
  static const _refreshKey = 'wasiati_refresh_token';
  final FlutterSecureStorage _secure;

  String? _accessToken;
  String? _refreshCache;

  TokenStore([FlutterSecureStorage? secure])
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  String? get accessToken => _accessToken;
  bool get hasAccessToken => _accessToken != null;

  Future<void> setTokens({required String accessToken, String? refreshToken}) async {
    _accessToken = accessToken;
    if (!Env.usesRefreshCookie && refreshToken != null) {
      _refreshCache = refreshToken;
      try {
        await _secure.write(key: _refreshKey, value: refreshToken);
      } catch (_) {/* keep in-memory copy even if the keystore is unavailable */}
    }
  }

  void setAccessToken(String token) => _accessToken = token;

  /// Refresh token for mobile; null on web (held in the httpOnly cookie).
  Future<String?> getRefreshToken() async {
    if (Env.usesRefreshCookie) return null;
    if (_refreshCache != null) return _refreshCache;
    try {
      _refreshCache = await _secure.read(key: _refreshKey);
    } catch (_) {
      _refreshCache = null;
    }
    return _refreshCache;
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshCache = null;
    if (!Env.usesRefreshCookie) {
      try {
        await _secure.delete(key: _refreshKey);
      } catch (_) {/* ignore */}
    }
  }

  /// Whether a prior session may be resumable (mobile: a stored refresh token).
  Future<bool> hasPersistedSession() async {
    if (Env.usesRefreshCookie) return true; // cookie may exist; router probes via /auth/refresh
    return (await getRefreshToken()) != null;
  }
}
