/// Non-web platforms: an [XFile] path is a real file on disk, not a `blob:` URL,
/// so there is nothing to free. The recorded temp file is the OS's to reap.
void revokeBlobUrl(String url) {}
