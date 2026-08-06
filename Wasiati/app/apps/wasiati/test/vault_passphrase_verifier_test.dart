import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/vault/data/vault_crypto.dart';

/// A wrong passphrase must not open the vault.
///
/// Unlock used to check the passphrase's LENGTH and nothing else. A typo derived a different
/// KEK and unlocked anyway — item labels are stored in plaintext, so the list rendered
/// exactly right — and every secret added afterwards was encrypted under a key the user
/// would never reproduce. The server holds no plaintext and there is no recovery
/// (DECISIONS §19; the screen's own warning says "not even by us"), so those items were
/// gone permanently and the vault ended up holding items under two different keys with
/// nothing anywhere reporting a problem.
///
/// AES-GCM is authenticated, which is what makes a cheap check possible at all: a wrong key
/// fails the MAC rather than returning plausible garbage.
const _salt = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 16 bytes, base64 — value is irrelevant, stability is not

Future<SecretKey> _kek(String passphrase) => VaultCrypto.deriveKek(passphrase, _salt);

void main() {
  test('the verifier opens under the SAME passphrase', () async {
    final k = await _kek('correcthorse!7');
    final v = await VaultCrypto.makeVerifier(k);
    expect(await VaultCrypto.verify(v, await _kek('correcthorse!7')), isTrue);
  });

  test('a one-character typo is REFUSED — the exact failure that lost the data', () async {
    // 'correcthorse!8' is 14 characters, so the old length check passed it happily.
    final v = await VaultCrypto.makeVerifier(await _kek('correcthorse!7'));
    expect(await VaultCrypto.verify(v, await _kek('correcthorse!8')), isFalse);
  });

  test('a different salt is refused too, so a re-keyed vault cannot be half-written', () async {
    final v = await VaultCrypto.makeVerifier(await _kek('correcthorse!7'));
    // A different 16-byte salt (bytes 0x01..0x10), as a per-user salt actually is.
    final other = await VaultCrypto.deriveKek('correcthorse!7', 'AQIDBAUGBwgJCgsMDQ4PEA==');
    expect(await VaultCrypto.verify(v, other), isFalse);
  });

  test('a corrupt or truncated verifier fails CLOSED rather than throwing', () async {
    // Refusing to unlock costs a retry. Unlocking under the wrong key costs the secrets, so
    // anything unreadable is treated as a refusal — never as "probably fine".
    final k = await _kek('correcthorse!7');
    for (final junk in ['', 'not-a-blob', 'a.b.c', 'AAAA.BBBB', 'AAAA.BBBB.CCCC']) {
      expect(await VaultCrypto.verify(junk, k), isFalse, reason: 'should refuse: "$junk"');
    }
  });

  test('canDecrypt proves a key against a REAL item, which is how an old vault adopts one', () async {
    final right = await _kek('correcthorse!7');
    final wrong = await _kek('correcthorse!8');
    final enc = await VaultCrypto.encrypt('hunter2', right);

    expect(await VaultCrypto.canDecrypt(enc.ciphertext, enc.encryptedDataKey, right), isTrue);
    expect(await VaultCrypto.canDecrypt(enc.ciphertext, enc.encryptedDataKey, wrong), isFalse);
  });

  test('canDecrypt does not throw on a mangled item', () async {
    final k = await _kek('correcthorse!7');
    expect(await VaultCrypto.canDecrypt('garbage', 'garbage', k), isFalse);
  });

  test('two verifiers from the same passphrase differ but both verify', () async {
    // A fresh nonce each time, so the blob is not a stable fingerprint of the passphrase
    // sitting in the database.
    final a = await VaultCrypto.makeVerifier(await _kek('correcthorse!7'));
    final b = await VaultCrypto.makeVerifier(await _kek('correcthorse!7'));
    expect(a, isNot(b));
    final k = await _kek('correcthorse!7');
    expect(await VaultCrypto.verify(a, k), isTrue);
    expect(await VaultCrypto.verify(b, k), isTrue);
  });

  test('round-trip still works — the check did not break the vault', () async {
    final k = await _kek('correcthorse!7');
    final enc = await VaultCrypto.encrypt('hunter2', k);
    expect(await VaultCrypto.decrypt(enc.ciphertext, enc.encryptedDataKey, k), 'hunter2');
  });
}
