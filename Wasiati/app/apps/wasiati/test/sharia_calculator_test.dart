import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

// Mirrors backend/src/wills/sharia-calculator.spec.ts so the Dart port stays in
// lock-step with the authoritative TypeScript calculator, including the two
// special cases (al-Gharrawayn and 'asaba ma'a al-ghayr).
Heir h(HeirRelation r, [String? name]) => Heir(r, name ?? r.name);

double pct(List<Heir> heirs, String rel, [String madhhab = 'JUMHUR']) =>
    calculateShariaShares(heirs, madhhab: madhhab)
        .where((s) => s.heirRelation == rel)
        .fold(0.0, (a, s) => a + s.sharePercent);

double total(List<Heir> heirs, [String madhhab = 'JUMHUR']) =>
    calculateShariaShares(heirs, madhhab: madhhab).fold(0.0, (a, s) => a + s.sharePercent);

void main() {
  group('displayed shares sum to EXACTLY 100.00 (largest-remainder rounding)', () {
    // Mirrors backend/src/wills/sharia-calculator.spec.ts. Independent 2-dp rounding
    // drifts thirds-heavy cases to 100.01; apportionment forces an exact total.
    final cases = <String, List<Heir>>{
      'wife + 2 sons + daughter + mother + father': [
        h(HeirRelation.wife), h(HeirRelation.son, 's1'), h(HeirRelation.son, 's2'),
        h(HeirRelation.daughter), h(HeirRelation.mother), h(HeirRelation.father),
      ],
      'daughter + mother + father (thirds)': [h(HeirRelation.daughter), h(HeirRelation.mother), h(HeirRelation.father)],
      'gharrawayn: husband + mother + father': [h(HeirRelation.husband), h(HeirRelation.mother), h(HeirRelation.father)],
      '2 daughters + mother (radd)': [h(HeirRelation.daughter, 'd1'), h(HeirRelation.daughter, 'd2'), h(HeirRelation.mother)],
    };
    cases.forEach((label, heirs) {
      test('$label → exactly 100.00', () {
        // Compare in basis points so float noise can't fail a correct total.
        expect((total(heirs) * 100).round(), 10000);
      });
    });
  });

  group('calculateShariaShares (core)', () {
    test('wife + son + daughter → 12.5 / 58.33 / 29.17', () {
      final heirs = [h(HeirRelation.wife), h(HeirRelation.son), h(HeirRelation.daughter)];
      expect(pct(heirs, 'WIFE'), closeTo(12.5, 0.1));
      expect(pct(heirs, 'SON'), closeTo(58.33, 0.1));
      expect(pct(heirs, 'DAUGHTER'), closeTo(29.17, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('daughter + mother + father → 50 / 16.67 / 33.33', () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.mother), h(HeirRelation.father)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'MOTHER'), closeTo(16.67, 0.1));
      expect(pct(heirs, 'FATHER'), closeTo(33.33, 0.1));
    });
  });

  group('al-Gharrawayn (spouse + both parents)', () {
    test('husband + mother + father → 50 / 16.67 / 33.33', () {
      final heirs = [h(HeirRelation.husband), h(HeirRelation.mother), h(HeirRelation.father)];
      expect(pct(heirs, 'HUSBAND'), closeTo(50, 0.1));
      expect(pct(heirs, 'MOTHER'), closeTo(16.67, 0.1)); // 1/3 of the 1/2 remainder
      expect(pct(heirs, 'FATHER'), closeTo(33.33, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('wife + mother + father → 25 / 25 / 50', () {
      final heirs = [h(HeirRelation.wife), h(HeirRelation.mother), h(HeirRelation.father)];
      expect(pct(heirs, 'WIFE'), closeTo(25, 0.1));
      expect(pct(heirs, 'MOTHER'), closeTo(25, 0.1)); // 1/3 of the 3/4 remainder
      expect(pct(heirs, 'FATHER'), closeTo(50, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('not gharrawayn when a child is present (mother → 1/6)', () {
      final heirs = [h(HeirRelation.husband), h(HeirRelation.mother), h(HeirRelation.father), h(HeirRelation.son)];
      expect(pct(heirs, 'MOTHER'), closeTo(16.67, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });
  });

  group("'asaba ma'a al-ghayr (sisters residuary with daughters)", () {
    test('two daughters + full sister → 66.67 / 33.33 (no awl)', () {
      final heirs = [h(HeirRelation.daughter, 'd1'), h(HeirRelation.daughter, 'd2'), h(HeirRelation.fullSister)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(66.67, 0.1));
      expect(pct(heirs, 'FULL_SISTER'), closeTo(33.33, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('husband + daughter + full sister → 25 / 50 / 25', () {
      final heirs = [h(HeirRelation.husband), h(HeirRelation.daughter), h(HeirRelation.fullSister)];
      expect(pct(heirs, 'HUSBAND'), closeTo(25, 0.1));
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'FULL_SISTER'), closeTo(25, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('full sisters alone stay Quranic sharers with radd', () {
      final heirs = [h(HeirRelation.fullSister, 's1'), h(HeirRelation.fullSister, 's2')];
      expect(total(heirs), closeTo(100, 0.1));
    });
  });

  group('grandfather with siblings (madhhab)', () {
    test('JUMHUR default: grandfather + full brother → 50 / 50 (muqasama)', () {
      final heirs = [h(HeirRelation.grandfather), h(HeirRelation.fullBrother)];
      expect(pct(heirs, 'GRANDFATHER'), closeTo(50, 0.1));
      expect(pct(heirs, 'FULL_BROTHER'), closeTo(50, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('JUMHUR: grandfather + full sister → 66.67 / 33.33 (2:1)', () {
      final heirs = [h(HeirRelation.grandfather), h(HeirRelation.fullSister)];
      expect(pct(heirs, 'GRANDFATHER'), closeTo(66.67, 0.1));
      expect(pct(heirs, 'FULL_SISTER'), closeTo(33.33, 0.1));
    });

    test('HANAFI: grandfather blocks the siblings (100 / 0)', () {
      final heirs = [h(HeirRelation.grandfather), h(HeirRelation.fullBrother)];
      final res = calculateShariaShares(heirs, madhhab: 'HANAFI');
      expect(res.firstWhere((s) => s.heirRelation == 'GRANDFATHER').sharePercent, closeTo(100, 0.1));
      expect(res.where((s) => s.heirRelation == 'FULL_BROTHER').fold(0.0, (a, s) => a + s.sharePercent), 0);
    });
  });

  // --- Grandfather WITH a female descendant + siblings (Zayd doctrine). Regression
  // guard for the bug where the grandfather took the whole residue (siblings → 0) in
  // every school when a daughter was present. The muqasama must still apply outside
  // Hanafi; the grandfather takes the best of muqasama / 1/3-residue / 1/6-estate.
  // Mirrors backend/src/wills/sharia-calculator.spec.ts. ---
  group('grandfather + female descendant + siblings (Zayd)', () {
    test('JUMHUR: grandfather + daughter + full brother → 50 / 25 / 25 (muqasama, not block)', () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.grandfather), h(HeirRelation.fullBrother)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1)); // fixed 1/2
      expect(pct(heirs, 'GRANDFATHER'), closeTo(25, 0.1)); // muqasama = 1/2 of the 1/2 remainder
      expect(pct(heirs, 'FULL_BROTHER'), closeTo(25, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('JUMHUR: grandfather + daughter + full sister → 50 / 33.33 / 16.67', () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.grandfather), h(HeirRelation.fullSister)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'GRANDFATHER'), closeTo(33.33, 0.1)); // muqasama 2:1 over the 1/2 remainder
      expect(pct(heirs, 'FULL_SISTER'), closeTo(16.67, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('JUMHUR: grandfather + daughter + 2 full brothers → 50 / 16.67 / 33.33', () {
      final heirs = [
        h(HeirRelation.daughter),
        h(HeirRelation.grandfather),
        h(HeirRelation.fullBrother, 'b1'),
        h(HeirRelation.fullBrother, 'b2'),
      ];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'GRANDFATHER'), closeTo(16.67, 0.1)); // muqasama = 2/6 of the 1/2 remainder
      expect(pct(heirs, 'FULL_BROTHER'), closeTo(33.33, 0.1)); // 16.67 each
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('JUMHUR: husband + daughter + grandfather + full brother → GF gets the 1/6-estate floor', () {
      final heirs = [
        h(HeirRelation.husband),
        h(HeirRelation.daughter),
        h(HeirRelation.grandfather),
        h(HeirRelation.fullBrother),
      ];
      // Husband 1/4, daughter 1/2, remainder 1/4. GF best-of: muqasama 1/8, 1/3-remainder
      // 1/12, 1/6-estate floor 1/6 → GF 1/6; brother gets the rest of the remainder (1/12).
      expect(pct(heirs, 'HUSBAND'), closeTo(25, 0.1));
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'GRANDFATHER'), closeTo(16.67, 0.1));
      expect(pct(heirs, 'FULL_BROTHER'), closeTo(8.33, 0.1));
      expect(total(heirs), closeTo(100, 0.1));
    });

    test('HANAFI: grandfather + daughter + full brother still blocks the brother (50 / 50 / 0)', () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.grandfather), h(HeirRelation.fullBrother)];
      expect(pct(heirs, 'DAUGHTER', 'HANAFI'), closeTo(50, 0.1));
      expect(pct(heirs, 'GRANDFATHER', 'HANAFI'), closeTo(50, 0.1)); // fixed 1/6 + the whole residue
      expect(pct(heirs, 'FULL_BROTHER', 'HANAFI'), 0);
      expect(total(heirs, 'HANAFI'), closeTo(100, 0.1));
    });
  });

  group('extended heirs (Flutter mirror matches backend)', () {
    test("son's daughter completes 2/3 with a daughter + father → 50 / 16.67 / 33.33", () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.sonDaughter), h(HeirRelation.father)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'SON_DAUGHTER'), closeTo(16.67, 0.1));
      expect(pct(heirs, 'FATHER'), closeTo(33.33, 0.1));
    });

    test('consanguine sister is residuary (maʿa al-ghayr) with a daughter → 50 / 50', () {
      final heirs = [h(HeirRelation.daughter), h(HeirRelation.consanguineSister)];
      expect(pct(heirs, 'DAUGHTER'), closeTo(50, 0.1));
      expect(pct(heirs, 'CONSANGUINE_SISTER'), closeTo(50, 0.1));
    });

    test('paternal uncle is residuary with a wife → 25 / 75', () {
      final heirs = [h(HeirRelation.wife), h(HeirRelation.fullUncle)];
      expect(pct(heirs, 'WIFE'), closeTo(25, 0.1));
      expect(pct(heirs, 'FULL_UNCLE'), closeTo(75, 0.1));
    });

    test('a father blocks the paternal grandmother, not the maternal one', () {
      final matGm = [h(HeirRelation.father), h(HeirRelation.maternalGrandmother), h(HeirRelation.son)];
      expect(pct(matGm, 'MATERNAL_GRANDMOTHER'), closeTo(16.67, 0.1));
      final patGm = [h(HeirRelation.father), h(HeirRelation.paternalGrandmother), h(HeirRelation.son)];
      expect(pct(patGm, 'PATERNAL_GRANDMOTHER'), 0);
    });
  });

  // Mirrors the backend's `school-aware radd and bayt al-mal` suite. The live
  // preview must never show a Maliki user the Jumhur division.
  group('school-aware radd and bayt al-mal', () {
    final wifeMother = [h(HeirRelation.wife), h(HeirRelation.mother)];

    test('EVERY school returns the surplus by radd (contemporary practice)', () {
      for (final school in ['JUMHUR', 'HANAFI', 'HANBALI', 'MALIKI', 'SHAFII']) {
        expect(pct(wifeMother, 'WIFE', school), closeTo(25, 0.1));
        expect(pct(wifeMother, 'MOTHER', school), closeTo(75, 0.1));
        expect(pct(wifeMother, kBaytAlMal, school), 0);
        expect(total(wifeMother, school), closeTo(100, 0.1));
      }
    });

    test('an unclaimable surplus goes to the treasury rather than vanishing', () {
      final lone = [h(HeirRelation.husband)];
      expect(pct(lone, 'HUSBAND'), closeTo(50, 0.1));
      expect(pct(lone, kBaytAlMal), closeTo(50, 0.1));
      expect(total(lone), closeTo(100, 0.1));
    });

    test('Hanafi grandfather blocks full siblings; other schools share by muqasama', () {
      final gf = [h(HeirRelation.grandfather), h(HeirRelation.fullBrother)];
      expect(pct(gf, 'GRANDFATHER', 'HANAFI'), closeTo(100, 0.1));
      expect(pct(gf, 'FULL_BROTHER', 'HANAFI'), 0);
      for (final school in ['JUMHUR', 'MALIKI', 'SHAFII', 'HANBALI']) {
        expect(pct(gf, 'GRANDFATHER', school), closeTo(50, 0.1));
        expect(pct(gf, 'FULL_BROTHER', school), closeTo(50, 0.1));
      }
    });
  });
}
