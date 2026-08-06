/// Storage usage against the per-user 1 GB quota (backend GET /files/quota).
class StorageQuota {
  final int usedBytes;
  final int quotaBytes;
  final int remainingBytes;

  const StorageQuota({required this.usedBytes, required this.quotaBytes, required this.remainingBytes});

  double get fraction => quotaBytes == 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);
  bool get isFull => remainingBytes <= 0;

  factory StorageQuota.fromJson(Map<String, dynamic> j) => StorageQuota(
        usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
        quotaBytes: (j['quotaBytes'] as num?)?.toInt() ?? 0,
        remainingBytes: (j['remainingBytes'] as num?)?.toInt() ?? 0,
      );
}

/// A file the user has uploaded (backend FileObject).
class StoredFile {
  final String id;
  final String kind; // 'video_legacy' | 'id_document' | 'death_certificate'
  final String key;
  final String contentType;
  final int sizeBytes;

  /// Malware-scan verdict: 'CLEAN' | 'PENDING' | 'INFECTED'. The download
  /// endpoint refuses anything but CLEAN, so the UI checks this FIRST and says
  /// why, instead of letting the tap die on a 403.
  final String scanStatus;

  const StoredFile({
    required this.id,
    required this.kind,
    required this.key,
    required this.contentType,
    required this.sizeBytes,
    this.scanStatus = 'CLEAN',
  });

  bool get scanPending => scanStatus == 'PENDING';
  bool get scanFailed => scanStatus == 'INFECTED';

  factory StoredFile.fromJson(Map<String, dynamic> j) => StoredFile(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? '',
        key: (j['key'] as String?) ?? '',
        contentType: (j['contentType'] as String?) ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        // Absent on older payloads -> assume CLEAN, matching the schema default;
        // the server re-checks on download either way.
        scanStatus: (j['scanStatus'] as String?) ?? 'CLEAN',
      );
}

/// A presigned direct-to-storage upload (backend POST /files/presign).
class PresignedUpload {
  final String uploadUrl;
  final String key;
  final Map<String, String> requiredHeaders;
  final int maxBytes;
  final String kind;

  const PresignedUpload({
    required this.uploadUrl,
    required this.key,
    required this.requiredHeaders,
    required this.maxBytes,
    required this.kind,
  });

  factory PresignedUpload.fromJson(Map<String, dynamic> j) => PresignedUpload(
        uploadUrl: j['uploadUrl'] as String,
        key: j['key'] as String,
        requiredHeaders: ((j['requiredHeaders'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        maxBytes: (j['maxBytes'] as num?)?.toInt() ?? 0,
        kind: (j['kind'] as String?) ?? '',
      );
}

/// The content types the backend accepts for `video_legacy`, in the order it lists
/// them (UPLOAD_KINDS in files.service.ts). It matches EXACTLY — no parameters, no
/// wildcards — which is what [videoUploadContentType] exists to respect.
const videoLegacyContentTypes = ['video/mp4', 'video/webm', 'video/quicktime'];

/// Normalises a recorder's mime to the bare `type/subtype` the backend allow-list
/// expects, falling back to mp4 for anything unrecognised.
///
/// camera_web negotiates a PARAMETERISED type: it prefers `video/webm;codecs="vp9,opus"`
/// and stamps that whole string, quotes included, onto the recorded XFile
/// (camera.dart:601-616 → :506-510). presign compares with `includes(ct)`, so passing
/// it through rejected every Chrome, Edge and Firefox recording at zero seconds.
/// Safari was the only browser that ever worked, because it falls through to bare
/// `video/mp4` — which is why this survived to here.
String videoUploadContentType(String? recordedMimeType) {
  final base = (recordedMimeType ?? '').split(';').first.trim().toLowerCase();
  return videoLegacyContentTypes.contains(base) ? base : 'video/mp4';
}

/// The content types the backend accepts for `death_certificate`, and the per-file
/// ceiling — both mirrored from UPLOAD_KINDS in files.service.ts.
///
/// Checked client-side for the same reason [videoLegacyMaxBytes] is: presign rejects
/// an oversized or wrong-typed file anyway, but only after the claimant has already
/// pulled the whole thing onto the heap, and on this flow a rejected presign costs
/// one of the token's two storage operations.
const deathCertificateContentTypes = ['application/pdf', 'image/jpeg', 'image/png', 'image/heic'];
const deathCertificateMaxBytes = 15 * 1024 * 1024;

/// Extensions the picker offers, in the order they map to the types above.
const deathCertificateExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'heic'];

/// Maps a picked file's extension to the exact bare `type/subtype` the backend
/// allow-list expects, or null if it is not an accepted kind. Returns the bare type
/// with no parameters — presign compares with `includes(ct)`, so anything
/// parameterised is refused (the bug that broke every non-Safari video upload).
String? deathCertificateContentType(String? extension) => switch ((extension ?? '').toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' => 'image/heic',
      _ => null,
    };

/// Human-readable byte size, e.g. "1.2 GB", "340 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || v % 1 == 0 ? 0 : 1)} ${units[i]}';
}
