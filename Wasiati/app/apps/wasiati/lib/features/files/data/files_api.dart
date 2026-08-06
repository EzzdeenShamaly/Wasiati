import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/file_models.dart';

/// Client for the direct-to-storage upload pipeline. Bytes go straight to storage
/// via a presigned PUT — they never pass through the Wasiati API — while presign,
/// confirm, quota, list and delete are owner-scoped API calls.
class FilesApi {
  final Dio _dio;
  FilesApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<StorageQuota> quota() => _guard(() async {
        final res = await _dio.get('/files/quota');
        return StorageQuota.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PresignedUpload> presign({
    required String kind,
    required String contentType,
    required int sizeBytes,
  }) =>
      _guard(() async {
        final res = await _dio.post('/files/presign',
            data: {'kind': kind, 'contentType': contentType, 'sizeBytes': sizeBytes});
        return PresignedUpload.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<StoredFile> confirm({
    required String kind,
    required String key,
    required String contentType,
    required int sizeBytes,
  }) =>
      _guard(() async {
        final res = await _dio.post('/files/confirm',
            data: {'kind': kind, 'key': key, 'contentType': contentType, 'sizeBytes': sizeBytes});
        return StoredFile.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<List<StoredFile>> list(String kind) => _guard(() async {
        final res = await _dio.get('/files/$kind');
        return (res.data as List).map((e) => StoredFile.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<void> delete(String id) => _guard(() => _dio.delete('/files/$id'));

  /// A short-lived presigned URL for one of the user's own files
  /// (GET /files/:id/download -> {url}). The server refuses anything that has
  /// not passed the malware scan (403, with a message saying whether it is
  /// still being scanned or blocked), and pins the served content-type to the
  /// file's kind — a legacy video plays inline, everything else attaches.
  Future<String> downloadUrl(String id) => _guard(() async {
        final res = await _dio.get('/files/$id/download');
        return ((res.data as Map).cast<String, dynamic>())['url'] as String;
      });

  /// PUTs the bytes straight to the presigned storage URL. Uses a bare Dio (no auth
  /// header, no base URL) because the URL is already signed and points at storage.
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
}
