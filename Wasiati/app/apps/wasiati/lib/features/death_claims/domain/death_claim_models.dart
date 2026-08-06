/// Why release would or would not succeed right now, as the SERVER computed it.
///
/// `listPendingReview` has always attached this to every APPROVED claim, for the stated
/// purpose of letting the admin UI "enable/disable the Release button and show WHY without
/// re-deriving server rules client-side". The client parsed none of it and rendered an
/// always-enabled button, so an admin learned the answer by pressing it — and then pressed
/// it again the next day to poll for readiness, because nothing else on the screen would say.
///
/// Deliberately carries no heir names: the server stopped sending them, because the roster
/// of a private will is not an operator's to read.
class ReleaseGate {
  final bool ready;
  final DateTime? releasableAt;
  final bool safetyWindowElapsed;
  final bool willSealed;
  final bool trusteeConfirmed;
  final bool overrideActive;
  final int outstandingHeirConfirmations;
  final bool heirsSatisfied;

  const ReleaseGate({
    required this.ready,
    required this.safetyWindowElapsed,
    required this.willSealed,
    required this.trusteeConfirmed,
    required this.overrideActive,
    required this.outstandingHeirConfirmations,
    required this.heirsSatisfied,
    this.releasableAt,
  });

  factory ReleaseGate.fromJson(Map<String, dynamic> j) => ReleaseGate(
        ready: (j['ready'] as bool?) ?? false,
        releasableAt: DateTime.tryParse((j['releasableAt'] as String?) ?? ''),
        safetyWindowElapsed: (j['safetyWindowElapsed'] as bool?) ?? false,
        willSealed: (j['willSealed'] as bool?) ?? false,
        trusteeConfirmed: (j['trusteeConfirmed'] as bool?) ?? false,
        overrideActive: (j['overrideActive'] as bool?) ?? false,
        outstandingHeirConfirmations: (j['outstandingHeirConfirmations'] as num?)?.toInt() ?? 0,
        heirsSatisfied: (j['heirsSatisfied'] as bool?) ?? false,
      );
}

class DeathClaim {
  final String id;
  final String? willId;
  final String submittedByName;
  final String submittedByPhone;
  final String status; // SUBMITTED | UNDER_REVIEW | APPROVED | REJECTED | RELEASED
  final String? certificateFileUrl;
  final String? rejectionReason;
  final String? ownerEmail;

  /// Present on APPROVED claims only — the server attaches it to nothing else.
  final ReleaseGate? releaseGate;

  const DeathClaim({
    required this.id,
    required this.submittedByName,
    required this.submittedByPhone,
    required this.status,
    this.willId,
    this.certificateFileUrl,
    this.rejectionReason,
    this.ownerEmail,
    this.releaseGate,
  });

  factory DeathClaim.fromJson(Map<String, dynamic> j) {
    final will = (j['will'] as Map?)?.cast<String, dynamic>();
    final owner = (will?['owner'] as Map?)?.cast<String, dynamic>();
    return DeathClaim(
      id: j['id'] as String,
      willId: j['willId'] as String?,
      submittedByName: j['submittedByName'] as String,
      submittedByPhone: j['submittedByPhone'] as String,
      status: j['status'] as String,
      certificateFileUrl: j['certificateFileUrl'] as String?,
      rejectionReason: j['rejectionReason'] as String?,
      ownerEmail: owner?['email'] as String?,
      releaseGate: j['releaseGate'] == null
          ? null
          : ReleaseGate.fromJson((j['releaseGate'] as Map).cast<String, dynamic>()),
    );
  }
}
