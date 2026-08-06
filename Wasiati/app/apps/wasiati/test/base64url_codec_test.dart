import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/utils/base64url.dart';

/// Pins the WebAuthn base64url codec in BOTH directions.
///
/// This codec is the seam between the backend's @simplewebauthn JSON transport
/// (base64url, no padding) and the browser's ArrayBuffers. Every way of getting
/// it wrong — padding kept, standard `+/` alphabet, asymmetric round trips —
/// compiles fine and passes any test that doesn't look at the actual characters;
/// the failure would only surface as the browser rejecting the challenge at
/// runtime. So the vectors here check the exact output, not just consistency.
void main() {
  group('base64UrlEncodeNoPad', () {
    test('uses the url-safe alphabet where standard base64 would use + and /', () {
      // 0xFB 0xFF encodes to "+/8=" in standard base64 — the url form must be "-_8".
      expect(base64UrlEncodeNoPad([0xFB, 0xFF]), '-_8');
    });

    test('emits NO padding for every remainder class (len % 3 == 0, 1, 2)', () {
      expect(base64UrlEncodeNoPad(utf8.encode('foobar')), 'Zm9vYmFy'); // 6 bytes
      expect(base64UrlEncodeNoPad(utf8.encode('fooba')), 'Zm9vYmE'); // 5 bytes
      expect(base64UrlEncodeNoPad(utf8.encode('foob')), 'Zm9vYg'); // 4 bytes
      expect(base64UrlEncodeNoPad(<int>[]), '');
    });

    test('a 32-byte challenge (the WebAuthn norm) becomes exactly 43 chars, no =', () {
      final encoded = base64UrlEncodeNoPad(List<int>.generate(32, (i) => i * 7 % 256));
      expect(encoded.length, 43);
      expect(encoded, isNot(contains('=')));
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
    });
  });

  group('base64UrlDecode', () {
    test('decodes unpadded url-safe input (what the server actually sends)', () {
      expect(base64UrlDecode('-_8'), [0xFB, 0xFF]);
      expect(base64UrlDecode('Zm9vYg'), utf8.encode('foob'));
    });

    test('tolerates padded and standard-alphabet variants', () {
      expect(base64UrlDecode('-_8='), [0xFB, 0xFF]);
      expect(base64UrlDecode('+/8='), [0xFB, 0xFF]);
      expect(base64UrlDecode('Zm9vYmE='), utf8.encode('fooba'));
    });

    test('rejects garbage loudly instead of feeding it to the authenticator', () {
      expect(() => base64UrlDecode('!!!'), throwsFormatException);
      expect(() => base64UrlDecode('ab cd'), throwsFormatException);
    });

    test('decodes the empty string to zero bytes', () {
      expect(base64UrlDecode(''), isEmpty);
    });
  });

  test('round-trips every length 0..64 exactly (deterministic bytes)', () {
    for (var n = 0; n <= 64; n++) {
      final bytes = List<int>.generate(n, (i) => (i * 131 + n * 17) % 256);
      final encoded = base64UrlEncodeNoPad(bytes);
      expect(base64UrlDecode(encoded), bytes, reason: 'length $n failed the round trip');
      expect(encoded, isNot(contains('=')), reason: 'length $n leaked padding');
    }
  });

  test('agrees with dart:convert on a known RFC 4648 vector', () {
    // RFC 4648 §10: BASE64("foobar") = "Zm9vYmFy".
    expect(base64UrlEncodeNoPad(utf8.encode('foobar')), base64.encode(utf8.encode('foobar')));
  });
}
