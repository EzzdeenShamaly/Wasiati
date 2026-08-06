import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/wills/domain/will_export_gate.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

/// Client mirror of the backend export gate (`WillsService.assertExportable`), and
/// these tests mirror its spec. The owner's rule: the will may always be VIEWED,
/// but there is no PDF export until BOTH the witness quorum has SIGNED **and** the
/// trustee has CONFIRMED. Each half must block on its own — a gate that checks only
/// one would enable the button early and hand the user a 403.

Witness w(String status) => Witness(id: 'w', fullName: 'W', phone: '+1', status: status);
Trustee t(String status) => Trustee(id: 't', fullName: 'T', phone: '+1', status: status);

WillExportGate gate({
  int required = 2,
  List<Witness>? witnesses = const [],
  List<Trustee>? trustees = const [],
}) =>
    WillExportGate.of(requiredWitnesses: required, witnesses: witnesses, trustees: trustees);

void main() {
  group('WillExportGate — enables the PDF only when BOTH halves are done', () {
    test('exportable once the quorum signed and the trustee confirmed', () {
      final g = gate(witnesses: [w('SIGNED'), w('SIGNED')], trustees: [t('CONFIRMED')]);
      expect(g.exportable, isTrue);
      expect(g.hasOutstanding, isFalse);
    });

    test('BLOCKS on an unconfirmed trustee even with a full witness quorum', () {
      final g = gate(witnesses: [w('SIGNED'), w('SIGNED')], trustees: [t('PENDING')]);
      expect(g.exportable, isFalse);
      expect(g.trusteeOutstanding, isTrue);
      expect(g.outstandingWitnesses, 0); // the witnesses are done; only the trustee is named
    });

    test('BLOCKS when there is no trustee at all', () {
      final g = gate(witnesses: [w('SIGNED'), w('SIGNED')], trustees: []);
      expect(g.exportable, isFalse);
      expect(g.trusteeOutstanding, isTrue);
    });

    test('BLOCKS on a missing witness even with the trustee confirmed', () {
      final g = gate(witnesses: [w('SIGNED'), w('PENDING')], trustees: [t('CONFIRMED')]);
      expect(g.exportable, isFalse);
      expect(g.outstandingWitnesses, 1); // -> "Waiting on: 1 witness"
      expect(g.trusteeOutstanding, isFalse);
    });

    test('names BOTH parties when neither half is done', () {
      final g = gate(witnesses: [w('PENDING'), w('PENDING')], trustees: [t('PENDING')]);
      expect(g.exportable, isFalse);
      expect(g.outstandingWitnesses, 2); // -> "Waiting on: 2 witnesses · trustee"
      expect(g.trusteeOutstanding, isTrue);
    });

    test('counts only SIGNED witnesses — a full-size PENDING roster is not a quorum', () {
      final g = gate(witnesses: [w('PENDING'), w('PENDING')], trustees: [t('CONFIRMED')]);
      expect(g.exportable, isFalse);
      expect(g.outstandingWitnesses, 2);
    });

    test('accepts any ONE confirmed trustee among several rows', () {
      final g = gate(witnesses: [w('SIGNED'), w('SIGNED')], trustees: [t('PENDING'), t('CONFIRMED')]);
      expect(g.exportable, isTrue);
    });

    test('honours a will that requires more than the default two witnesses', () {
      final g = gate(required: 3, witnesses: [w('SIGNED'), w('SIGNED')], trustees: [t('CONFIRMED')]);
      expect(g.exportable, isFalse);
      expect(g.outstandingWitnesses, 1);
    });

    test('never reports negative outstanding when extra witnesses signed', () {
      final g = gate(required: 2, witnesses: [w('SIGNED'), w('SIGNED'), w('SIGNED')], trustees: [t('CONFIRMED')]);
      expect(g.outstandingWitnesses, 0);
      expect(g.exportable, isTrue);
    });

    test('status matching is case-insensitive', () {
      final g = gate(witnesses: [w('signed'), w('Signed')], trustees: [t('confirmed')]);
      expect(g.exportable, isTrue);
    });
  });

  group('WillExportGate — unknown state never enables the button', () {
    test('not ready (and not exportable) while the witness roster is loading', () {
      final g = gate(witnesses: null, trustees: [t('CONFIRMED')]);
      expect(g.ready, isFalse);
      expect(g.exportable, isFalse);
      expect(g.hasOutstanding, isFalse); // nothing to name yet -> "Checking signatures…"
    });

    test('not ready while the trustee roster is loading', () {
      final g = gate(witnesses: [w('SIGNED'), w('SIGNED')], trustees: null);
      expect(g.ready, isFalse);
      expect(g.exportable, isFalse);
    });

    test('not ready while both rosters are loading', () {
      final g = gate(witnesses: null, trustees: null);
      expect(g.ready, isFalse);
      expect(g.exportable, isFalse);
    });
  });
}
