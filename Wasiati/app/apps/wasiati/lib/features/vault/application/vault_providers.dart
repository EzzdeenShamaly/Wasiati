import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/vault_api.dart';
import '../domain/vault_models.dart';

final vaultApiProvider = Provider<VaultApi>((ref) => VaultApi(ref.read(apiClientProvider).dio));

final vaultListProvider = FutureProvider.autoDispose<List<VaultItem>>((ref) => ref.read(vaultApiProvider).list());
