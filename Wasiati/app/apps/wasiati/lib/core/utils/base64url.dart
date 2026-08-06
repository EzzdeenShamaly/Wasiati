import 'dart:convert';
import 'dart:typed_data';

/// Base64url codec for the WebAuthn ceremonies (passkeys).
///
/// The server side (@simplewebauthn/server) speaks the WebAuthn JSON transport:
/// every binary field — challenge, user.id, credential ids, the attestation and
/// assertion payloads — travels as base64url WITHOUT padding. The browser APIs
/// (`navigator.credentials.create()` / `.get()`) deal only in raw ArrayBuffers.
/// These two functions are the seam between them.
///
/// The trap: any mismatch (padding kept, standard `+/` alphabet, double
/// encoding) still compiles and still ships bytes — the failure only appears at
/// runtime as the browser or server rejecting the challenge. Hence this
/// dedicated codec, pinned in both directions by base64url_codec_test.dart.

/// Encodes [bytes] as base64url without padding — the exact form the WebAuthn
/// JSON transport uses and @simplewebauthn/server verifies.
String base64UrlEncodeNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url into bytes for the browser's ArrayBuffer fields.
///
/// Tolerant on input ([base64.normalize] restores padding and maps a standard
/// `+/` alphabet), strict on garbage (throws [FormatException]) — a corrupt
/// challenge must fail HERE, loudly, not inside the authenticator.
Uint8List base64UrlDecode(String source) => base64.decode(base64.normalize(source));
