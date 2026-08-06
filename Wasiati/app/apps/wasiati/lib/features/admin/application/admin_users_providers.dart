import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../data/admin_users_api.dart';

final adminUsersApiProvider = Provider<AdminUsersApi>((ref) => AdminUsersApi(ref.read(apiClientProvider).dio));

final adminUsersProvider = FutureProvider.autoDispose<AdminUsersData>((ref) => ref.read(adminUsersApiProvider).load());
