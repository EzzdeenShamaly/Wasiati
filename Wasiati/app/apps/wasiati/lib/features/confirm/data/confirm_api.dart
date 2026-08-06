import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// Client for the PUBLIC trustee-confirmation and witness-signing endpoints.
///
/// These are reached from an SMS link by someone who has NO Wasiati account —
/// the trustee or witness named on someone else's will — so, like the portal,
/// they must run on a bare Dio (no AuthInterceptor, no token store; see
/// portal_client.dart for the full reasoning). The only credential in play is
/// the one-time SMS code the person types.
///
/// Neither send-code endpoint ever echoes the code (they answer `{sent:true}`
/// no matter what), and neither confirm endpoint distinguishes a wrong code
/// from an expired one — the backend's single "Invalid or expired code."
/// message is shown verbatim rather than being second-guessed here.
class ConfirmApi {
  final Dio _dio;
  ConfirmApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Texts the trustee their 6-digit confirmation code (throttled 3/min/IP).
  Future<void> sendTrusteeCode(String trusteeId) =>
      _guard(() => _dio.post('/trustees/$trusteeId/send-code'));

  /// Confirms the trustee role. 400 on a wrong/expired code, 404 on an unknown id.
  Future<void> confirmTrustee(String trusteeId, {required String code}) =>
      _guard(() => _dio.post('/trustees/$trusteeId/confirm', data: {'code': code}));

  /// Texts the witness their 6-digit signing code (throttled 3/min/IP).
  Future<void> sendWitnessCode(String witnessId) =>
      _guard(() => _dio.post('/witnesses/$witnessId/send-code'));

  /// Records the witness signature. [legalName] must match the name the owner
  /// put on the roster (the backend compares case/diacritic/whitespace-
  /// insensitively) or the signature is refused with a specific 400 message.
  ///
  /// [signatureData] follows the owner-signing convention established in
  /// review_seal_screen.dart:34 — a digital acknowledgement marker, not a
  /// drawn image. The identity evidence is the OTP + the legal-name match
  /// (idMatchStatus MATCHED), plus the IP/user-agent the server records.
  Future<void> confirmWitness(
    String witnessId, {
    required String code,
    required String legalName,
    String signatureData = 'digital-acknowledgement',
  }) =>
      _guard(() => _dio.post('/witnesses/$witnessId/confirm', data: {
            'code': code,
            'legalName': legalName,
            'signatureData': signatureData,
          }));
}
