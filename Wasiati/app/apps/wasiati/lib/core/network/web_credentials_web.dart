import 'package:dio/dio.dart';
import 'package:dio/browser.dart';

/// Web: send credentials (the httpOnly refresh cookie) on cross-origin XHRs so
/// the backend can read/set the wasiati_refresh cookie.
void enableWebCredentials(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is BrowserHttpClientAdapter) {
    adapter.withCredentials = true;
  }
}
