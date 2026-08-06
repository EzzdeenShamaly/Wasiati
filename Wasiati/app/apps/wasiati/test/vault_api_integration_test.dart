import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/vault/data/vault_api.dart';
import 'package:wasiati/features/vault/data/vault_crypto.dart';

/// Proves the server only ever stores ciphertext and the client round-trips it.
/// Uses admin (has the vault entitlement). An ApiException from any call (backend
/// down or 429 throttle) skips the test.
void main() {
  test('vault stores only ciphertext; client decrypts it back', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000', headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    try {
      final res = await loginFully(dio, email: 'admin@wasiati.test', password: 'AdminPass12345');
      dio.options.headers['Authorization'] = 'Bearer ${res.accessToken}';
      final uid = res.user.id;

      final kek = await VaultCrypto.deriveKek('vault-pass-123', uid);
      const plaintext = 'super-secret-value-42';
      final enc = await VaultCrypto.encrypt(plaintext, kek);

      final api = VaultApi(dio);
      await api.add(label: 'Integration secret', ciphertext: enc.ciphertext, encryptedDataKey: enc.encryptedDataKey);

      final item = (await api.list()).firstWhere((i) => i.label == 'Integration secret');
      expect(item.ciphertext, isNot(contains('super-secret'))); // server never sees plaintext
      final out = await VaultCrypto.decrypt(item.ciphertext, item.encryptedDataKey, kek);
      expect(out, plaintext);

      await api.delete(item.id);
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 25)));
}
