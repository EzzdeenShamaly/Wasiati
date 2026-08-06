import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/identity_api.dart';

final identityApiProvider = Provider<IdentityApi>((ref) => IdentityApi(ref.read(apiClientProvider).dio));

final identityStatusProvider =
    FutureProvider.autoDispose<IdentityStatus>((ref) => ref.read(identityApiProvider).status());
