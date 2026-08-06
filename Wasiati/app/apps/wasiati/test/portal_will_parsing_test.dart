import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/portal/domain/portal_models.dart';

/// Nothing the server sends to the heirs may be dropped on the floor.
///
/// GET /portal/will returns seven fields. PortalWill.fromJson parsed four. The three it
/// discarded were the inventory — with accountRef deliberately UNMASKED, in the endpoint's
/// own words "so the heirs can walk into the institution and locate the asset" — the
/// funeral wishes, and the guardianship of minor children. A testator who recorded six
/// accounts with their IBANs and branch numbers handed his daughter a personal message and
/// a list of percentages. The PDF was no fallback: its renderer receives only
/// type/label/institution/value/currency. At day 90 the purge erased the references for good.
///
/// This is the shape of bug a parser test catches and nothing else does: the data arrived,
/// the screen was correct about what it was given, and the loss was silent at every layer.
const _serverPayload = {
  'estateName': 'owner@example.com',
  'personalMessage': 'For my children',
  'shariaShares': [
    {'heirName': 'Aisha', 'heirRelation': 'DAUGHTER', 'sharePercent': 25.0},
  ],
  'bequests': [
    {'beneficiaryName': 'Masjid al-Noor', 'sharePercent': 10.0, 'notes': 'For the library'},
  ],
  'assets': [
    {
      'type': 'BANK_ACCOUNT',
      'label': 'Current account',
      'institution': 'Emirates NBD',
      'estimatedValue': 210000,
      'currency': 'AED',
      'notes': 'Salary account',
      'contactPhone': '+97142000000',
      'contactEmail': 'branch@enbd.example',
      'accountRef': 'AE070331234567890123456',
    },
    {'type': 'LIABILITY', 'label': 'Car loan', 'estimatedValue': 30000, 'currency': 'AED'},
  ],
  'funeralWishes': {'sunnah': true, 'simple': true, 'local': false, 'azaa': true},
  'guardianship': {
    'mode': 'NAMED',
    'name': 'Khalid Rahman',
    'phone': '+971500000000',
    'email': 'khalid@example.com',
  },
};

void main() {
  test('keeps every field the endpoint sends, not just the four it used to read', () {
    final w = PortalWill.fromJson(Map<String, dynamic>.from(_serverPayload));

    expect(w.estateName, 'owner@example.com');
    expect(w.personalMessage, 'For my children');
    expect(w.shariaShares, hasLength(1));
    expect(w.bequests, hasLength(1));

    // The three that were being discarded.
    expect(w.assets, hasLength(2));
    expect(w.funeralWishes, isNotNull);
    expect(w.guardianship, isNotNull);
  });

  test('carries the account reference through UNMASKED — it is the point of the field', () {
    final w = PortalWill.fromJson(Map<String, dynamic>.from(_serverPayload));
    final bank = w.assets.first;

    expect(bank.accountRef, 'AE070331234567890123456');
    // Masking here would defeat the reason the server sends it unmasked. Pinned explicitly
    // so a well-meaning "don't show full IBANs" change has to argue with this test first.
    expect(bank.accountRef, isNot(contains('*')));
    expect(bank.contactPhone, '+97142000000');
    expect(bank.contactEmail, 'branch@enbd.example');
    expect(bank.notes, 'Salary account');
    expect(bank.institution, 'Emirates NBD');
    expect(bank.estimatedValue, 210000);
    expect(bank.currency, 'AED');
  });

  test('reads guardianship in full, including how to reach them', () {
    final g = PortalWill.fromJson(Map<String, dynamic>.from(_serverPayload)).guardianship!;
    expect(g.mode, 'NAMED');
    expect(g.name, 'Khalid Rahman');
    expect(g.phone, '+971500000000');
    expect(g.email, 'khalid@example.com');
  });

  test('survives a sparse asset row — every field but type and label is optional', () {
    final w = PortalWill.fromJson({
      'estateName': 'o@x.com',
      'assets': [
        {'type': 'OTHER', 'label': 'A box of documents'},
      ],
    });
    final a = w.assets.single;
    expect(a.label, 'A box of documents');
    expect(a.accountRef, isNull);
    expect(a.estimatedValue, isNull);
  });

  test('an estate with no inventory parses to empty, never to null', () {
    // The released view branches on isNotEmpty; a null here would be a crash on the one
    // screen a grieving family cannot afford to lose.
    final w = PortalWill.fromJson({'estateName': 'o@x.com'});
    expect(w.assets, isEmpty);
    expect(w.funeralWishes, isNull);
    expect(w.guardianship, isNull);
  });
}
