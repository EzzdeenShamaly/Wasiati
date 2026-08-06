import 'package:dio/dio.dart';
import '../config/env.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
// Enables withCredentials on web so the httpOnly refresh cookie flows.
import 'web_credentials_stub.dart' if (dart.library.html) 'web_credentials_web.dart';

/// Builds the app's Dio instance: base URL from Env, the auth interceptor
/// (token attach + silent refresh), and web credential support.
class ApiClient {
  final Dio dio;
  ApiClient._(this.dio);

  factory ApiClient.create({
    required TokenStore tokenStore,
    required void Function() onSessionExpired,
  }) {
    BaseOptions baseOptions() => BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
        );

    final refreshDio = Dio(baseOptions());
    final dio = Dio(baseOptions());
    enableWebCredentials(dio);
    enableWebCredentials(refreshDio);

    final interceptor = AuthInterceptor(
      tokenStore: tokenStore,
      refreshDio: refreshDio,
      onSessionExpired: onSessionExpired,
    );
    interceptor.retryDio = dio;
    dio.interceptors.add(interceptor);

    return ApiClient._(dio);
  }
}
