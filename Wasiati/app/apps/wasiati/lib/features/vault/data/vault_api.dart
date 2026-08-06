import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/vault_models.dart';

class VaultApi {
  final Dio _dio;
  VaultApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Everything unlock needs before it can trust a passphrase: the per-user PBKDF2 salt,
  /// the passphrase verifier if this vault has one, and whether it holds any items.
  ///
  /// [hasItems] decides what a verifier-less vault can be checked against — an existing
  /// item proves the KEK, an empty vault has nothing to prove it and is adopting its
  /// passphrase for the first time.
  Future<VaultKdf> kdf() => _guard(() async {
        final res = await _dio.get('/vault/kdf');
        final m = (res.data as Map).cast<String, dynamic>();
        return VaultKdf(
          salt: m['salt'] as String,
          verifier: m['verifier'] as String?,
          hasItems: (m['hasItems'] as bool?) ?? false,
        );
      });

  /// Records this vault's passphrase check. Write-once server-side: a later attempt is a
  /// no-op, so a typo can never replace the verifier and lock the real passphrase out.
  Future<void> setVerifier(String verifier) =>
      _guard(() => _dio.post('/vault/kdf/verifier', data: {'verifier': verifier}));

  Future<void> add({required String label, required String ciphertext, required String encryptedDataKey}) =>
      _guard(() => _dio.post('/vault/items', data: {
            'label': label,
            'ciphertext': ciphertext,
            'encryptedDataKey': encryptedDataKey,
          }));

  Future<List<VaultItem>> list() => _guard(() async {
        final res = await _dio.get('/vault/items');
        return (res.data as List).map((e) => VaultItem.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<void> delete(String id) => _guard(() => _dio.delete('/vault/items/$id'));
}
