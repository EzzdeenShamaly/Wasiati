import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/zakat_api.dart';
import '../domain/zakat_models.dart';

final zakatApiProvider = Provider<ZakatApi>((ref) => ZakatApi(ref.read(apiClientProvider).dio));

final zakatEstimateProvider =
    FutureProvider.autoDispose<ZakatEstimate>((ref) => ref.read(zakatApiProvider).estimate());
