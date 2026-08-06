import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/death_claims_api.dart';
import '../domain/death_claim_models.dart';

final deathClaimsApiProvider = Provider<DeathClaimsApi>((ref) => DeathClaimsApi(ref.read(apiClientProvider).dio));

final pendingClaimsProvider = FutureProvider.autoDispose<List<DeathClaim>>(
  (ref) => ref.read(deathClaimsApiProvider).pending(),
);
