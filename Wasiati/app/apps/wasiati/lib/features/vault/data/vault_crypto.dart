import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Client-side envelope encryption for the vault. The server only ever stores
/// the two ciphertext blobs — it can never read a secret.
///
/// - A fresh random 256-bit `dataKey` encrypts each value (AES-GCM) -> ciphertext.
/// - The `dataKey` is wrapped (AES-GCM) with a KEK derived from the user's
///   passphrase via PBKDF2-HMAC-SHA256 -> encryptedDataKey.
///
/// The vault's confidentiality rests entirely on the passphrase: the KEK is derived
/// from it with PBKDF2-HMAC-SHA256 at 210 000 iterations (OWASP 2023 minimum) over a
/// per-user RANDOM 16-byte salt (generated with a CSPRNG and persisted server-side at
/// vault creation, fetched at unlock). A random-per-user salt defeats cross-user
/// rainbow tables AND precomputation, so a stolen ciphertext is expensive to
/// brute-force offline and must be attacked one user at a time.
///
/// Zero-knowledge: the server stores only the two ciphertext blobs + the (non-secret)
/// salt. It never receives the passphrase, the KEK, or any plaintext.
class VaultCrypto {
  static final _aes = AesGcm.with256bits();
  // 210k iterations per OWASP 2023 for PBKDF2-HMAC-SHA256. Raising this invalidates
  // any vault items encrypted at a lower count (acceptable pre-production; version the
  // params if the vault ever holds real data before this ships).
  static final _pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 210000, bits: 256);

  /// Derives the KEK from the passphrase and the per-user salt fetched from the
  /// server (GET /vault/kdf). The salt is random and stable per user; it is not
  /// secret — its job is to make each user's derivation unique and unpredictable.
  static Future<SecretKey> deriveKek(String passphrase, String saltBase64) {
    final salt = base64.decode(saltBase64);
    return _pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  }

  static String _pack(SecretBox box) =>
      '${base64.encode(box.nonce)}.${base64.encode(box.cipherText)}.${base64.encode(box.mac.bytes)}';

  static SecretBox _unpack(String s) {
    final p = s.split('.');
    return SecretBox(base64.decode(p[1]), nonce: base64.decode(p[0]), mac: Mac(base64.decode(p[2])));
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static Future<({String ciphertext, String encryptedDataKey})> encrypt(String value, SecretKey kek) async {
    final dataKey = SecretKey(_randomBytes(32));
    final valueBox = await _aes.encrypt(utf8.encode(value), secretKey: dataKey);
    final wrapBox = await _aes.encrypt(await dataKey.extractBytes(), secretKey: kek);
    return (ciphertext: _pack(valueBox), encryptedDataKey: _pack(wrapBox));
  }

  static Future<String> decrypt(String ciphertext, String encryptedDataKey, SecretKey kek) async {
    final dataKeyBytes = await _aes.decrypt(_unpack(encryptedDataKey), secretKey: kek);
    final plain = await _aes.decrypt(_unpack(ciphertext), secretKey: SecretKey(dataKeyBytes));
    return utf8.decode(plain);
  }

  /// The fixed plaintext behind the passphrase check. Its content is irrelevant — only
  /// that both sides agree on it — but it is versioned so a future KDF change can tell an
  /// old verifier from a wrong passphrase instead of confusing the two.
  static const _verifierPlaintext = 'wasiati-vault-verifier-v1';

  /// A blob that proves a passphrase, stored once per vault.
  ///
  /// Unlock previously checked only that the typed passphrase was at least 10 characters.
  /// A typo derived a different KEK and unlocked anyway — labels are plaintext, so the list
  /// looked right — and every secret added afterwards was encrypted under a key the user
  /// would never reproduce. There is no recovery (DECISIONS §19), so those items were gone.
  static Future<String> makeVerifier(SecretKey kek) async =>
      _pack(await _aes.encrypt(utf8.encode(_verifierPlaintext), secretKey: kek));

  /// True when [kek] is the key this vault was locked with.
  ///
  /// AES-GCM is authenticated, so a wrong key fails the MAC rather than returning garbage —
  /// there is no ambiguity to interpret. Any malformed or unreadable blob is treated as a
  /// failure: refusing to unlock is recoverable, writing under the wrong key is not.
  static Future<bool> verify(String verifier, SecretKey kek) async {
    try {
      final plain = await _aes.decrypt(_unpack(verifier), secretKey: kek);
      return utf8.decode(plain) == _verifierPlaintext;
    } catch (_) {
      return false;
    }
  }

  /// True when [kek] can open an item this vault already holds.
  ///
  /// The adoption path for a vault created before verifiers existed: prove the key against
  /// real ciphertext, and only then record a verifier.
  static Future<bool> canDecrypt(String ciphertext, String encryptedDataKey, SecretKey kek) async {
    try {
      await decrypt(ciphertext, encryptedDataKey, kek);
      return true;
    } catch (_) {
      return false;
    }
  }
}
