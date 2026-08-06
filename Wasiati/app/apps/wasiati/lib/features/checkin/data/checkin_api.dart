import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';

/// The user's inactivity check-in — a death trigger, not a marketing ping.
class CheckinStatus {
  final bool enabled;
  final String frequency; // MONTHLY | QUARTERLY | YEARLY
  final DateTime? lastConfirmedAt;
  final int remindersSent;
  final bool trusteeAlerted;
  final String claimInitPolicy; // TRUSTEE_ONLY | HEIRS_WITH_DOCUMENTS | BOTH

  const CheckinStatus({
    required this.enabled,
    required this.frequency,
    required this.lastConfirmedAt,
    required this.remindersSent,
    required this.trusteeAlerted,
    required this.claimInitPolicy,
  });

  factory CheckinStatus.fromJson(Map<String, dynamic> j) => CheckinStatus(
        enabled: (j['checkinEnabled'] as bool?) ?? false,
        frequency: (j['checkinFrequency'] as String?) ?? 'QUARTERLY',
        lastConfirmedAt: j['lastCheckinAt'] == null ? null : DateTime.tryParse(j['lastCheckinAt'] as String),
        remindersSent: (j['remindersSent'] as num?)?.toInt() ?? 0,
        trusteeAlerted: (j['trusteeAlerted'] as bool?) ?? false,
        claimInitPolicy: (j['claimInitPolicy'] as String?) ?? 'BOTH',
      );
}

class CheckinApi {
  final Dio _dio;
  CheckinApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CheckinStatus> status() => _guard(() async {
        final res = await _dio.get('/checkin');
        return CheckinStatus.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<void> update({bool? enabled, String? frequency}) => _guard(() => _dio.put('/checkin', data: {
        if (enabled != null) 'checkinEnabled': enabled,
        if (frequency != null) 'checkinFrequency': frequency,
      }));

  /// Resets the reminder count and clears any trustee alert.
  Future<void> confirmAlive() => _guard(() => _dio.post('/checkin/confirm'));

  Future<void> setClaimPolicy(String policy) =>
      _guard(() => _dio.put('/checkin/claim-policy', data: {'claimInitPolicy': policy}));
}
