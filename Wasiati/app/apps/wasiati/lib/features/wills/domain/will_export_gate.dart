import 'wills_models.dart';

/// Client mirror of the backend export gate (`WillsService.assertExportable`).
///
/// The owner's rule: a will may always be VIEWED, but the PDF must not be exported
/// until BOTH halves of the ceremony are done — the witness quorum has SIGNED
/// **and** the trustee has CONFIRMED (by e-sign or SMS code; both land as
/// CONFIRMED). The server is the authority and refuses with a 403 regardless; this
/// exists so the button can be disabled with a reason that NAMES who is still
/// outstanding, instead of firing a request that bounces.
class WillExportGate {
  /// False while either roster is still loading. We cannot yet say who is
  /// outstanding, and must not claim the will is exportable on unknown state.
  final bool ready;

  /// How many witnesses still have to sign to reach the will's quorum.
  final int outstandingWitnesses;

  /// True until at least one trustee has confirmed.
  final bool trusteeOutstanding;

  const WillExportGate({
    required this.ready,
    required this.outstandingWitnesses,
    required this.trusteeOutstanding,
  });

  /// Both halves done — and only once we actually know both rosters.
  bool get exportable => ready && outstandingWitnesses == 0 && !trusteeOutstanding;

  /// True when the gate can name outstanding parties (loaded, but not yet clear).
  bool get hasOutstanding => ready && !exportable;

  /// Resolves the gate from the rosters. Pass null for a roster still in flight.
  ///
  /// `requiredWitnesses` mirrors the will's own threshold (schema default 2), so a
  /// will that demands more than two is gated on its real number, not a hardcoded one.
  factory WillExportGate.of({
    required int requiredWitnesses,
    List<Witness>? witnesses,
    List<Trustee>? trustees,
  }) {
    if (witnesses == null || trustees == null) {
      return const WillExportGate(ready: false, outstandingWitnesses: 0, trusteeOutstanding: true);
    }
    // Only a SIGNED witness counts — a full-size PENDING roster is not a quorum.
    final signed = witnesses.where((w) => w.status.toUpperCase() == 'SIGNED').length;
    return WillExportGate(
      ready: true,
      outstandingWitnesses: (requiredWitnesses - signed).clamp(0, requiredWitnesses),
      // No trustee row at all is the absence of confirmation, not a pass.
      trusteeOutstanding: !trustees.any((t) => t.status.toUpperCase() == 'CONFIRMED'),
    );
  }
}
