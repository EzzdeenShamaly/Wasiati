import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/assets_api.dart';
import '../domain/asset_models.dart';

final assetsApiProvider = Provider<AssetsApi>((ref) => AssetsApi(ref.read(apiClientProvider).dio));

final assetsProvider =
    FutureProvider.autoDispose.family<List<EstateAsset>, String>((ref, willId) => ref.read(assetsApiProvider).list(willId));
