import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/burial_api.dart';
import '../domain/burial_models.dart';

final burialApiProvider = Provider<BurialApi>((ref) => BurialApi(ref.read(apiClientProvider).dio));

final burialListProvider = FutureProvider.autoDispose<List<BurialEstimate>>(
  (ref) => ref.read(burialApiProvider).list(),
);

/// ADMIN queue: requests awaiting a manually-sourced quote (+ recently answered).
final adminBurialQuotesProvider = FutureProvider.autoDispose<List<BurialQuoteRequest>>(
  (ref) => ref.read(burialApiProvider).adminPendingQuotes(),
);
