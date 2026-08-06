import 'package:web/web.dart' as web;

/// Web: frees the `blob:` URL behind a recorded [XFile].
///
/// camera_web mints one per recording via `URL.createObjectURL` (camera.dart:507)
/// and never revokes it — there is no `revokeObjectURL` anywhere in the package —
/// so the Blob is pinned for the life of the page. Without this, every retake
/// leaks a whole video: five retakes of an 80 MB take hold ~400 MB until reload.
///
/// Only safe to call once nothing will read the file again: cross_file re-hydrates
/// the blob by XHR-ing this same URL, so revoking before [XFile.readAsBytes]
/// resolves breaks the read.
void revokeBlobUrl(String url) {
  if (!url.startsWith('blob:')) return;
  web.URL.revokeObjectURL(url);
}
