import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/death_claims/domain/death_claim_models.dart';

/// The admin queue's Release button now answers from the server's own gate.
///
/// `listPendingReview` attaches a releaseGate to every APPROVED claim, for the stated
/// purpose of letting the UI "enable/disable the Release button and show WHY without
/// re-deriving server rules client-side". DeathClaim.fromJson parsed none of it, so the
/// button rendered always-enabled: an admin learned the answer by pressing it and getting
/// "2 of 2 heir(s) have not confirmed", then pressed it again the next day to poll, because
/// nothing on screen said when the window opened.
const _approvedNotReady = {
  'id': 'c1',
  'submittedByName': 'Yusuf',
  'submittedByPhone': '+971500000000',
  'status': 'APPROVED',
  'will': {'owner': {'email': 'owner@x.com'}},
  'releaseGate': {
    'releasableAt': '2026-08-03T09:00:00.000Z',
    'safetyWindowElapsed': false,
    'willSealed': true,
    'trusteeConfirmed': true,
    'overrideActive': false,
    'outstandingHeirConfirmations': 2,
    'heirsSatisfied': false,
    'heirs': [
      {'heirContactId': 'h1', 'reachable': true, 'confirmed': false, 'confirmedAt': null},
    ],
    'ready': false,
  },
};

void main() {
  test('parses the gate the server already sends', () {
    final g = DeathClaim.fromJson(Map<String, dynamic>.from(_approvedNotReady)).releaseGate!;

    expect(g.ready, isFalse);
    expect(g.safetyWindowElapsed, isFalse);
    expect(g.outstandingHeirConfirmations, 2);
    expect(g.releasableAt, DateTime.parse('2026-08-03T09:00:00.000Z'));
    expect(g.willSealed, isTrue);
    expect(g.trusteeConfirmed, isTrue);
  });

  test('a ready gate reads ready', () {
    final j = Map<String, dynamic>.from(_approvedNotReady);
    j['releaseGate'] = {
      ...(j['releaseGate']! as Map).cast<String, dynamic>(),
      'safetyWindowElapsed': true,
      'heirsSatisfied': true,
      'outstandingHeirConfirmations': 0,
      'ready': true,
    };
    expect(DeathClaim.fromJson(j).releaseGate!.ready, isTrue);
  });

  test('a claim that is not APPROVED carries no gate, and that is not an error', () {
    final j = Map<String, dynamic>.from(_approvedNotReady)..remove('releaseGate');
    j['status'] = 'SUBMITTED';
    expect(DeathClaim.fromJson(j).releaseGate, isNull);
  });

  test('defaults to NOT ready when the server sends a gate it does not understand', () {
    // Fail closed on the client too. A malformed gate that parsed as ready would re-enable
    // the button on an estate the server will refuse to release anyway — but the operator
    // would have been told it was fine.
    final j = Map<String, dynamic>.from(_approvedNotReady);
    j['releaseGate'] = <String, dynamic>{};
    final g = DeathClaim.fromJson(j).releaseGate!;
    expect(g.ready, isFalse);
    expect(g.releasableAt, isNull);
    expect(g.outstandingHeirConfirmations, 0);
  });
}
