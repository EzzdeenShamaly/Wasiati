import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

class AdminUser {
  final String id;
  final String email;
  final String? phone;
  final String region;
  final String role;
  final String idVerificationStatus;
  final bool emailVerified;
  final String? compTier;

  /// The user's highest active-subscription tier (BASIC/STANDARD/PREMIUM/ULTIMATE),
  /// or null when they have no active plan (free).
  final String? plan;
  final String? lastIp;
  final String createdAt;

  const AdminUser({
    required this.id,
    required this.email,
    required this.region,
    required this.role,
    required this.idVerificationStatus,
    required this.emailVerified,
    required this.createdAt,
    this.phone,
    this.compTier,
    this.plan,
    this.lastIp,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String?,
        region: j['region'] as String,
        role: j['role'] as String,
        idVerificationStatus: j['idVerificationStatus'] as String,
        emailVerified: j['emailVerified'] as bool? ?? false,
        compTier: j['compTier'] as String?,
        plan: j['plan'] as String?,
        lastIp: j['lastIp'] as String?,
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

class AdminUsersData {
  final int total;
  final List<AdminUser> users;
  final Map<String, int> byRegion;
  final Map<String, int> byStatus;
  final Map<String, int> byRole;
  final int sealedWills;
  final int sealedWillsWeek;

  const AdminUsersData({
    required this.total,
    required this.users,
    required this.byRegion,
    required this.byStatus,
    required this.byRole,
    required this.sealedWills,
    required this.sealedWillsWeek,
  });

  static Map<String, int> _intMap(dynamic m) =>
      (m as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? {};

  /// Number of users whose id-verification status is [status].
  int statusCount(String status) => byStatus[status] ?? 0;

  factory AdminUsersData.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    return AdminUsersData(
      total: (j['total'] as num?)?.toInt() ?? 0,
      users: ((j['users'] as List?) ?? const [])
          .map((e) => AdminUser.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      byRegion: _intMap(stats['byRegion']),
      byStatus: _intMap(stats['byStatus']),
      byRole: _intMap(stats['byRole']),
      sealedWills: (stats['sealedWills'] as num?)?.toInt() ?? 0,
      sealedWillsWeek: (stats['sealedWillsWeek'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminUsersApi {
  final Dio _dio;
  AdminUsersApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AdminUsersData> load() => _guard(() async {
        final res = await _dio.get('/admin/users');
        return AdminUsersData.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Grants [userId] a comped [tier] (BASIC/STANDARD/PREMIUM/ULTIMATE) with no
  /// payment — investor demos, QA and support accounts run on this. ADMIN is
  /// derived from the JWT server-side, never sent from here.
  Future<void> grantComp(String userId, String tier) =>
      _guard(() => _dio.post('/admin/users/$userId/comp', data: {'tier': tier}));

  /// Removes a comp grant; any paid subscription the user has is untouched.
  Future<void> revokeComp(String userId) => _guard(() => _dio.delete('/admin/users/$userId/comp'));
}
