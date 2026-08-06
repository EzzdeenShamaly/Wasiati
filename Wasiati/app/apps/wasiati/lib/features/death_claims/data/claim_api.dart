import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/portal_client.dart';
import '../../files/domain/file_models.dart';

/// Client for the accountless claim flow: the public lookup, the claim-scoped
/// death-certificate upload, and the submit.
///
/// Runs on [PortalClient]'s bare Dio, not the authenticated one — a claimant has no
/// account, and a signed-in visitor filing a claim on a relative's estate must not
/// have their Bearer token attached to these calls.
class ClaimApi {
  final Dio _dio;
  ClaimApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The way in. ALWAYS 202 `{ acknowledged: true }` — identical for an unknown
  /// person, a person with no sealed will, a claimant who is not a party, and a
  /// full match. There is deliberately no signal here to read, and the UI must not
  /// pretend to have found one.
  Future<void> lookup({required String deceasedContact, required String claimantContact}) => _guard(() async {
        await _dio.post('/death-claims/lookup', data: {
          'deceasedContact': deceasedContact,
          'claimantContact': claimantContact,
        });
      });

  /// Presign a death-certificate upload against the claim token. No `kind` and no
  /// `willId` are sent: the kind is nailed shut server-side and the estate comes
  /// out of the token.
  /// Is this link still alive? No side effect — the guard is the whole check.
  ///
  /// Called before the form is shown. Until this existed the first request carrying the
  /// token was the presign, so an expired link was discovered only after the claimant had
  /// filled the form and waited for a photograph to be read into memory.
  Future<void> session(String claimToken) => _guard(() async {
        await _dio.get('/claim/session', options: Options(headers: {'X-Claim-Token': claimToken}));
      });

  Future<PresignedUpload> presign({
    required String token,
    required String contentType,
    required int sizeBytes,
  }) =>
      _guard(() async {
        final res = await _dio.post(
          '/claim/uploads/presign',
          data: {'contentType': contentType, 'sizeBytes': sizeBytes},
          options: PortalClient.auth(token),
        );
        return PresignedUpload.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<StoredFile> confirm({
    required String token,
    required String key,
    required String contentType,
    required int sizeBytes,
  }) =>
      _guard(() async {
        final res = await _dio.post(
          '/claim/uploads/confirm',
          data: {'key': key, 'contentType': contentType, 'sizeBytes': sizeBytes},
          options: PortalClient.auth(token),
        );
        return StoredFile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// PUTs the bytes straight to the presigned storage URL. Bare Dio — the URL is
  /// already signed and points at storage, so neither the claim token nor any
  /// other credential belongs on it.
  Future<void> putBytes(PresignedUpload target, Uint8List bytes) => _guard(() async {
        await Dio().put(
          target.uploadUrl,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {...target.requiredHeaders, 'Content-Length': bytes.length},
            contentType: target.requiredHeaders['Content-Type'],
          ),
        );
      });

  /// Files the claim. Carries ONLY the name and the certificate's file id — willId,
  /// phone and role are read off the token and the body cannot influence them.
  Future<void> submit({
    required String token,
    required String submittedByName,
    required String certificateFileId,
  }) =>
      _guard(() async {
        await _dio.post(
          '/claim/submit',
          data: {'submittedByName': submittedByName, 'certificateFileId': certificateFileId},
          options: PortalClient.auth(token),
        );
      });
}

/// The full certificate upload: presign → PUT → confirm.
///
/// Mirrors [FileUploader] (files_providers.dart) deliberately, against the
/// claim-scoped routes. It is a separate class rather than a parameter on that one
/// because the two authenticate differently and the claim side has a hard
/// two-operation cap per token: one presign plus one confirm is exactly one
/// certificate, and a retry after a failed presign is refunded server-side.
class ClaimCertificateUploader {
  final ClaimApi _api;
  ClaimCertificateUploader(this._api);

  Future<StoredFile> upload({
    required String token,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final target = await _api.presign(token: token, contentType: contentType, sizeBytes: bytes.length);
    await _api.putBytes(target, bytes);
    return _api.confirm(token: token, key: target.key, contentType: contentType, sizeBytes: bytes.length);
  }
}
