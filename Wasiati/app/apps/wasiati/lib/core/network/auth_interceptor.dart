import 'package:dio/dio.dart';
import '../config/env.dart';
import '../storage/token_store.dart';

/// Attaches the access token + platform header to every request, and on a 401
/// performs a single-flight refresh then retries the original request once.
/// If refresh fails, the session is considered expired.
class AuthInterceptor extends Interceptor {
  final TokenStore tokenStore;
  final Dio refreshDio; // bare Dio (no interceptor) used only for /auth/refresh
  final void Function() onSessionExpired;
  late Dio retryDio; // the main Dio; set after construction

  Future<bool>? _refreshing;

  AuthInterceptor({
    required this.tokenStore,
    required this.refreshDio,
    required this.onSessionExpired,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Client-Platform'] = Env.clientPlatform;
    final token = tokenStore.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final isAuthPath = err.requestOptions.path.startsWith('/auth/');
    final alreadyRetried = err.requestOptions.extra['retried'] == true;

    if (status != 401 || isAuthPath || alreadyRetried) {
      return handler.next(err);
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      onSessionExpired();
      return handler.next(err);
    }

    try {
      final opts = err.requestOptions;
      opts.extra['retried'] = true;
      opts.headers['Authorization'] = 'Bearer ${tokenStore.accessToken}';
      final response = await retryDio.fetch(opts);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<bool> _refreshOnce() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    try {
      final body = <String, dynamic>{};
      if (!Env.usesRefreshCookie) {
        final rt = await tokenStore.getRefreshToken();
        if (rt == null) return false;
        body['refreshToken'] = rt;
      }
      final res = await refreshDio.post(
        '/auth/refresh',
        data: body,
        options: Options(headers: {'X-Client-Platform': Env.clientPlatform}),
      );
      final data = res.data as Map;
      final access = data['accessToken'] as String?;
      if (access == null) return false;
      await tokenStore.setTokens(accessToken: access, refreshToken: data['refreshToken'] as String?);
      return true;
    } catch (_) {
      return false;
    }
  }
}
