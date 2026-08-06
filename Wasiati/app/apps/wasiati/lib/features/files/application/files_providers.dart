import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/files_api.dart';
import '../domain/file_models.dart';

final filesApiProvider = Provider<FilesApi>((ref) => FilesApi(ref.read(apiClientProvider).dio));

/// The full upload: presign → PUT bytes to storage → confirm. Returns the stored
/// file record. The three-step dance is why callers use this rather than the API
/// directly — a half-completed upload (presigned but never confirmed) leaves no
/// FileObject row, so it doesn't count against quota.
final fileUploaderProvider = Provider<FileUploader>((ref) => FileUploader(ref.read(filesApiProvider)));

/// The backend's per-file ceiling for `video_legacy` (UPLOAD_KINDS in
/// files.service.ts). Mirrored here so an oversized recording is refused BEFORE it
/// is read: presign rejects it anyway, but [upload] only reaches presign after the
/// caller has already pulled the whole video onto the heap. Checking a blob's size
/// costs nothing; discovering the limit after a 500 MB read costs the tab.
/// MUST stay >= what [maxRecordingDuration] can actually produce, or a take runs to the
/// length limit and is then refused at upload — the one outcome worse than no limit at all.
/// At the pinned 1.2 Mbps video + 96 kbps audio a recording grows ~9.7 MB/minute, so the
/// one-hour cap yields ~582 MB. 750 MB leaves headroom for bitrate variance (the browser
/// treats the bitrate as a target, not a guarantee).
const videoLegacyMaxBytes = 750 * 1024 * 1024;

/// How long one take may run before the recorder stops itself. Owner's call: one hour.
///
/// Nothing previously limited LENGTH at all — the byte ceiling was standing in for it, and
/// badly: a take only reached the old 500 MB somewhere near fifty-five minutes, so no
/// recording of any realistic length was ever refused.
///
/// Two consequences of an hour worth knowing, neither hidden:
///  · ~582 MB per take, so ONE full-length video nearly fills the 1 GB per-user quota.
///    A user who records a second one will be told they are out of space.
///  · The whole blob is held in memory to upload, so an hour-long take on a modest phone
///    is the likeliest way this screen runs out of RAM.
const maxRecordingDuration = Duration(hours: 1);

/// How long before the cap the countdown starts. Five minutes: long enough to finish a
/// thought and say goodbye, which on an hour-long message is the part that matters.
const recordingWarnBefore = Duration(minutes: 5);

class FileUploader {
  final FilesApi _api;
  FileUploader(this._api);

  Future<StoredFile> upload({
    required String kind,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final target = await _api.presign(kind: kind, contentType: contentType, sizeBytes: bytes.length);
    await _api.putBytes(target, bytes);
    return _api.confirm(kind: kind, key: target.key, contentType: contentType, sizeBytes: bytes.length);
  }
}

final storageQuotaProvider = FutureProvider.autoDispose<StorageQuota>((ref) => ref.read(filesApiProvider).quota());

final videoFilesProvider =
    FutureProvider.autoDispose<List<StoredFile>>((ref) => ref.read(filesApiProvider).list('video_legacy'));
