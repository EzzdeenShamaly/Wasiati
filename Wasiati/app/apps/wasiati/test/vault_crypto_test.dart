import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/vault/data/vault_crypto.dart';

void main() {
  test('envelope encrypt/decrypt round-trips with the right passphrase', () async {
    final kek = await VaultCrypto.deriveKek('correct horse battery', base64.encode(List.filled(16, 7)));
    final enc = await VaultCrypto.encrypt('my bank password 123', kek);
    expect(enc.ciphertext, isNot(contains('bank password')));
    final out = await VaultCrypto.decrypt(enc.ciphertext, enc.encryptedDataKey, kek);
    expect(out, 'my bank password 123');
  });

  test('a wrong passphrase cannot decrypt', () async {
    final kek1 = await VaultCrypto.deriveKek('right-pass', base64.encode(List.filled(16, 9)));
    final kek2 = await VaultCrypto.deriveKek('wrong-pass', base64.encode(List.filled(16, 9)));
    final enc = await VaultCrypto.encrypt('secret', kek1);
    expect(() => VaultCrypto.decrypt(enc.ciphertext, enc.encryptedDataKey, kek2), throwsA(anything));
  });
}
