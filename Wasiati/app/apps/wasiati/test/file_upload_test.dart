import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/application/files_providers.dart';
import 'package:wasiati/features/files/data/files_api.dart';
import 'package:wasiati/features/files/domain/file_models.dart';

/// The upload is a three-step dance (presign → PUT → confirm); a half-done upload
/// must leave no confirmed record. These pin the model parsing and that the uploader
/// runs the steps in order with the presigned key threaded through.
class _FakeApi implements FilesApi {
  final List<String> calls = [];
  PresignedUpload? lastPresign;
  bool putCalled = false;

  @override
  Future<PresignedUpload> presign({required String kind, required String contentType, required int sizeBytes}) async {
    calls.add('presign:$kind:$sizeBytes');
    lastPresign = PresignedUpload(
      uploadUrl: 'https://storage/put',
      key: 'legacy-videos/u1/abc.mp4',
      requiredHeaders: {'Content-Type': contentType},
      maxBytes: 500 * 1024 * 1024,
      kind: kind,
    );
    return lastPresign!;
  }

  @override
  Future<void> putBytes(PresignedUpload target, Uint8List bytes) async {
    calls.add('put:${target.key}:${bytes.length}');
    putCalled = true;
  }

  @override
  Future<StoredFile> confirm({required String kind, required String key, required String contentType, required int sizeBytes}) async {
    calls.add('confirm:$key:$sizeBytes');
    return StoredFile(id: 'f1', kind: kind, key: key, contentType: contentType, sizeBytes: sizeBytes);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  group('StorageQuota', () {
    test('computes fraction and full-ness', () {
      final q = StorageQuota.fromJson({'usedBytes': 512 * 1024 * 1024, 'quotaBytes': 1024 * 1024 * 1024, 'remainingBytes': 512 * 1024 * 1024});
      expect(q.fraction, closeTo(0.5, 0.001));
      expect(q.isFull, isFalse);
    });

    test('is full when nothing remains, and clamps the bar at 1.0', () {
      final q = StorageQuota.fromJson({'usedBytes': 2000, 'quotaBytes': 1000, 'remainingBytes': 0});
      expect(q.isFull, isTrue);
      expect(q.fraction, 1.0);
    });
  });

  group('formatBytes', () {
    test('renders human sizes', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatBytes((1.5 * 1024 * 1024 * 1024).round()), '1.5 GB');
    });
  });

  group('videoUploadContentType', () {
    test("strips camera_web's codecs parameter — the whole reason web recording 400'd", () {
      // What Chrome/Edge/Firefox actually hand back: camera_web asks for
      // `video/webm;codecs="vp9,opus"` first and stamps the negotiated string, quotes
      // and all, onto the XFile. presign compares with an exact `includes(ct)`, so
      // forwarding it rejected every recording on those browsers at zero seconds.
      expect(videoUploadContentType('video/webm;codecs="vp9,opus"'), 'video/webm');
      expect(videoUploadContentType('video/webm;codecs=vp8'), 'video/webm');
      // Safari negotiates the bare type, which is why it was the only browser that
      // ever completed an upload — and why this went unnoticed.
      expect(videoUploadContentType('video/mp4'), 'video/mp4');
    });

    test('every result is a type the backend actually allows', () {
      // The contract this exists to satisfy. If UPLOAD_KINDS.video_legacy in
      // files.service.ts changes, this list — and this test — must move with it.
      for (final mime in [
        'video/webm;codecs="vp9,opus"',
        'video/mp4',
        'video/webm',
        'video/quicktime',
        'VIDEO/WEBM',
        'video/x-matroska;codecs=avc1',
        'application/octet-stream',
        '',
        null,
      ]) {
        expect(videoLegacyContentTypes, contains(videoUploadContentType(mime)), reason: 'mime: $mime');
      }
    });

    test('normalises case and whitespace, and defaults anything unrecognised to mp4', () {
      expect(videoUploadContentType('VIDEO/WEBM'), 'video/webm');
      expect(videoUploadContentType(' video/mp4 ; codecs=avc1 '), 'video/mp4');
      // An unknown container must not be forwarded and must not be guessed at — mp4 is
      // the safe default, and the backend re-checks the real bytes on confirm anyway.
      expect(videoUploadContentType('video/x-matroska'), 'video/mp4');
      expect(videoUploadContentType(null), 'video/mp4');
      expect(videoUploadContentType(''), 'video/mp4');
    });
  });

  group('PresignedUpload / StoredFile parsing', () {
    test('parses a presign response, defaulting a missing header map', () {
      final p = PresignedUpload.fromJson({'uploadUrl': 'https://s/put', 'key': 'k', 'maxBytes': 100, 'kind': 'video_legacy'});
      expect(p.uploadUrl, 'https://s/put');
      expect(p.requiredHeaders, isEmpty);
    });

    test('parses a stored file', () {
      final f = StoredFile.fromJson({'id': 'f1', 'kind': 'video_legacy', 'key': 'k', 'contentType': 'video/mp4', 'sizeBytes': 42});
      expect(f.sizeBytes, 42);
      expect(f.kind, 'video_legacy');
    });
  });

  group('FileUploader', () {
    test('runs presign → PUT → confirm IN ORDER, threading the presigned key', () async {
      final api = _FakeApi();
      final bytes = Uint8List.fromList(List.filled(2048, 7));
      final result = await FileUploader(api).upload(kind: 'video_legacy', contentType: 'video/mp4', bytes: bytes);

      expect(api.calls, [
        'presign:video_legacy:2048',
        'put:legacy-videos/u1/abc.mp4:2048', // PUT targets the presigned key
        'confirm:legacy-videos/u1/abc.mp4:2048', // confirm uses the SAME key
      ]);
      expect(result.id, 'f1');
    });

    test('does NOT confirm if the PUT fails (no orphaned quota charge)', () async {
      final api = _FakeApiPutFails();
      final bytes = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        FileUploader(api).upload(kind: 'video_legacy', contentType: 'video/mp4', bytes: bytes),
        throwsA(anything),
      );
      expect(api.confirmed, isFalse);
    });
  });
}

class _FakeApiPutFails implements FilesApi {
  bool confirmed = false;
  @override
  Future<PresignedUpload> presign({required String kind, required String contentType, required int sizeBytes}) async =>
      PresignedUpload(uploadUrl: 'x', key: 'legacy-videos/u1/a.mp4', requiredHeaders: const {}, maxBytes: 1, kind: kind);
  @override
  Future<void> putBytes(PresignedUpload target, Uint8List bytes) async => throw Exception('network');
  @override
  Future<StoredFile> confirm({required String kind, required String key, required String contentType, required int sizeBytes}) async {
    confirmed = true;
    return StoredFile(id: 'f', kind: kind, key: key, contentType: contentType, sizeBytes: sizeBytes);
  }
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
