import 'package:dio/dio.dart';

/// Non-web platforms: nothing to do (refresh token is sent in the request body).
void enableWebCredentials(Dio dio) {}
