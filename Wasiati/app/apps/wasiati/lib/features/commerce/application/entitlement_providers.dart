import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';

/// The signed-in user's effective entitlement: `{ tier, source, isAdmin, features }`.
/// `features` is a map like `{ aiIntake: true, videoMessages: true, ... }`.
///
/// Server is the source of truth (FeatureGuard enforces access); these flags only
/// decide what the UI OFFERS, never what it's allowed to do.
final entitlementProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(apiClientProvider).dio;
  final res = await dio.get('/entitlements/me');
  return (res.data as Map).cast<String, dynamic>();
});

/// True when the user's plan includes a given feature flag (e.g. 'aiIntake',
/// 'videoMessages'). Defaults to false while loading / on error — the UI then
/// shows the soft-sell path rather than a feature that would 403.
bool entitlementHas(Map<String, dynamic>? entitlement, String feature) {
  final features = entitlement?['features'];
  if (features is Map) return features[feature] == true;
  return false;
}
