import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// Errors the CLIENT invents must be readable in the reader's language.
///
/// The claim and portal flows both built their error text in the controller, which has no
/// locale, so it had no choice but to hardcode English — one of the two sentences duplicated
/// `authGenericError` verbatim while that key already carried a full Arabic translation. An
/// Arabic claimant uploading a death certificate on a slow connection got a bare English
/// sentence under a fully Arabic card, on the one screen where giving up is most costly.
///
/// The backend's own messages still pass through untouched. They are English-only today,
/// which is a real and larger gap: it needs error codes or server-side i18n, not a
/// client-side patch, so this pins the boundary rather than pretending to have closed it.
DioException _dio(DioExceptionType type, {dynamic data, int? status}) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: data == null && status == null
          ? null
          : Response(requestOptions: RequestOptions(path: '/x'), data: data, statusCode: status),
    );

void main() {
  late AppLocalizations en;
  late AppLocalizations ar;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  test('a connection failure reads in Arabic for an Arabic reader', () {
    final e = ApiException.fromDio(_dio(DioExceptionType.connectionError));
    expect(e.kind, ApiErrorKind.offline);
    expect(localizedApiMessage(ar, e), ar.apiOffline);
    expect(localizedApiMessage(ar, e), isNot(localizedApiMessage(en, e)));
  });

  test('a receive timeout counts as offline — it is the slow-connection case', () {
    // PortalClient sets a 20s receiveTimeout, so this is the shape a claimant on poor
    // coverage actually hits while a certificate uploads. It used to fall through to the
    // generic English default.
    expect(ApiException.fromDio(_dio(DioExceptionType.receiveTimeout)).kind, ApiErrorKind.offline);
    expect(ApiException.fromDio(_dio(DioExceptionType.sendTimeout)).kind, ApiErrorKind.offline);
  });

  test('an unreadable failure falls back to the TRANSLATED generic string', () {
    final e = ApiException.fromDio(_dio(DioExceptionType.unknown));
    expect(e.kind, ApiErrorKind.unknown);
    expect(localizedApiMessage(ar, e), ar.authGenericError);
    // The sentence the controller used to hardcode is exactly this ARB key's English value,
    // which is what made the duplication invisible.
    expect(en.authGenericError, 'Something went wrong. Please try again.');
  });

  test("the backend's own message is passed through, never overwritten", () {
    final e = ApiException.fromDio(
      _dio(DioExceptionType.badResponse, data: {'message': 'This link has expired or has already been used.'}, status: 401),
    );
    expect(e.kind, ApiErrorKind.server);
    expect(localizedApiMessage(ar, e), 'This link has expired or has already been used.');
    expect(e.statusCode, 401);
  });

  test('a validation list from class-validator survives as one readable block', () {
    final e = ApiException.fromDio(
      _dio(DioExceptionType.badResponse, data: {'message': ['name is too short', 'email must be an email']}, status: 400),
    );
    expect(e.message, 'name is too short\nemail must be an email');
    expect(e.kind, ApiErrorKind.server);
  });

  test('a non-ApiException still gets a translated sentence rather than a crash', () {
    expect(localizedApiMessage(ar, StateError('boom')), ar.authGenericError);
  });
}
