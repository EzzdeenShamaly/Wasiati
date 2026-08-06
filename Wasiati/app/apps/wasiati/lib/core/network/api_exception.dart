import 'package:dio/dio.dart';

import '../../l10n/app_localizations.dart';

/// Normalized API error surfaced to the UI. Extracts the backend's
/// `{ message, statusCode }` shape (class-validator / Nest exceptions).
/// Where an error's text came from, so the UI knows whether it can localise it.
///
/// [server] messages are the backend's own words and are passed through. The other two are
/// OURS — invented client-side when there is no body to read — and had been hardcoded
/// English sentences, one of which duplicated `authGenericError` verbatim while that key
/// already carried a full Arabic translation. On an Arabic-first product, on a
/// death-certificate upload, a bare English sentence under a fully Arabic card is the point
/// at which someone gives up.
enum ApiErrorKind { server, offline, unknown }

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final ApiErrorKind kind;

  ApiException(this.message, {this.statusCode, this.kind = ApiErrorKind.server});

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      final m = data['message'];
      return ApiException(
        m is List ? m.join('\n') : m.toString(),
        statusCode: e.response?.statusCode,
      );
    }
    final offline = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    // The English text stays as a last-resort fallback for anywhere without a BuildContext
    // (logs, tests). Screens should render `localizedApiMessage`, which ignores it.
    return ApiException(
      offline ? 'Cannot reach the server. Check your connection.' : 'Something went wrong. Please try again.',
      statusCode: e.response?.statusCode,
      kind: offline ? ApiErrorKind.offline : ApiErrorKind.unknown,
    );
  }

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// True when an error is a "this feature needs a higher plan" 403 — the signal to
/// show a [WasiatiUpgradePrompt] instead of a generic error.
bool isPaywall(Object e) => e is ApiException && e.statusCode == 403;

/// The sentence to actually SHOW for an error, in the reader's language.
///
/// Backend messages are passed through — they are specific and the server is the only
/// thing that knows them. (They are English-only today, which is a real gap and a bigger
/// one than this: it needs error codes or server-side i18n, not a client-side patch.)
/// Everything the CLIENT invented is localised, because there is no reason for it not to
/// be and an ARB key with a full Arabic translation already existed.
String localizedApiMessage(AppLocalizations l, Object e) {
  if (e is! ApiException) return l.authGenericError;
  return switch (e.kind) {
    ApiErrorKind.server => e.message,
    ApiErrorKind.offline => l.apiOffline,
    ApiErrorKind.unknown => l.authGenericError,
  };
}
