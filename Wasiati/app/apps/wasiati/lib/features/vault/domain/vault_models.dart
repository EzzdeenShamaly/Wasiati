class VaultItem {
  final String id;
  final String label;
  final String ciphertext;
  final String encryptedDataKey;

  const VaultItem({
    required this.id,
    required this.label,
    required this.ciphertext,
    required this.encryptedDataKey,
  });

  factory VaultItem.fromJson(Map<String, dynamic> j) => VaultItem(
        id: j['id'] as String,
        label: j['label'] as String,
        ciphertext: j['ciphertext'] as String,
        encryptedDataKey: j['encryptedDataKey'] as String,
      );
}

/// What GET /vault/kdf returns: the salt, the passphrase verifier (null until a vault has
/// adopted one), and whether the vault already holds items.
class VaultKdf {
  final String salt;
  final String? verifier;
  final bool hasItems;
  const VaultKdf({required this.salt, this.verifier, this.hasItems = false});
}
