// Which heirs the create-flow heir registry pre-loads (create-will step 2).
//
// These run the REAL fara'id engine and feed its output to the seeding rule, so they
// assert the property the owner actually asked for: the registry pre-loads exactly the
// heirs the live share preview gives a non-zero share to, and nobody a hijab rule
// blocks. The engine is not touched or stubbed — it is the qualification test.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/wills/domain/heir_registry_seed.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

/// The seed keys for a family, exactly as the create flow derives them: counters ->
/// heirs -> calculateShariaShares -> qualifyingHeirSeeds.
List<String> seedKeysFor(List<Heir> heirs, {String madhhab = 'JUMHUR'}) =>
    qualifyingHeirSeeds(calculateShariaShares(heirs, madhhab: madhhab)).map((s) => s.key).toList();

List<Heir> many(HeirRelation r, int n) => [for (var i = 0; i < n; i++) Heir(r, '${r.api} ${i + 1}')];

void main() {
  group('registryRelationFor', () {
    test('maps every fara\'id relation the create flow can produce', () {
      expect(registryRelationFor('WIFE'), 'wife');
      expect(registryRelationFor('HUSBAND'), 'husband');
      expect(registryRelationFor('SON'), 'son');
      expect(registryRelationFor('DAUGHTER'), 'daughter');
      expect(registryRelationFor('MOTHER'), 'mother');
      expect(registryRelationFor('FATHER'), 'father');
      expect(registryRelationFor('FULL_BROTHER'), 'brother');
      expect(registryRelationFor('FULL_SISTER'), 'sister');
    });

    test('distant agnates fall back to the roster\'s "other"', () {
      for (final r in const ['GRANDFATHER', 'MATERNAL_GRANDMOTHER', 'FULL_UNCLE', 'FULL_COUSIN', 'MATERNAL_SIBLING']) {
        expect(registryRelationFor(r), 'other', reason: r);
      }
    });

    test('bayt al-mal is never a registry row — it is a treasury, not a person', () {
      expect(registryRelationFor(kBaytAlMal), isNull);
    });
  });

  group('qualifyingHeirSeeds', () {
    test('seeds one key per heir, indexed within each relation', () {
      final keys = seedKeysFor([
        ...many(HeirRelation.wife, 2),
        ...many(HeirRelation.son, 2),
        ...many(HeirRelation.daughter, 1),
      ]);
      expect(keys, containsAll(['wife#0', 'wife#1', 'son#0', 'son#1', 'daughter#0']));
      expect(keys.length, 5);
    });

    test('a zero share is never seeded', () {
      const shares = [
        ShariaShare(heirRelation: 'SON', heirName: 'Son 1', sharePercent: 50),
        ShariaShare(heirRelation: 'FULL_BROTHER', heirName: 'Brother 1', sharePercent: 0),
      ];
      expect(qualifyingHeirSeeds(shares).map((s) => s.key), ['son#0']);
    });

    test('a bayt al-mal surplus is dropped, not turned into a row', () {
      // Wife alone, Maliki: no radd, so the surplus escheats and the engine returns a
      // BAYT_AL_MAL entry alongside her.
      final shares = calculateShariaShares([const Heir(HeirRelation.wife, 'Wife')], madhhab: 'MALIKI');
      expect(shares.any((s) => s.heirRelation == kBaytAlMal), isTrue, reason: 'engine should surface the surplus');
      expect(seedKeysFor([const Heir(HeirRelation.wife, 'Wife')], madhhab: 'MALIKI'), ['wife#0']);
    });
  });

  group('hijab — a blocked heir is never pre-loaded', () {
    test('a son blocks the brothers and sisters (the owner\'s own example)', () {
      final withoutSon = seedKeysFor([
        const Heir(HeirRelation.wife, 'Wife'),
        ...many(HeirRelation.fullBrother, 2),
      ]);
      expect(withoutSon, containsAll(['brother#0', 'brother#1']));

      final withSon = seedKeysFor([
        const Heir(HeirRelation.wife, 'Wife'),
        const Heir(HeirRelation.son, 'Son'),
        ...many(HeirRelation.fullBrother, 2),
      ]);
      expect(withSon, containsAll(['wife#0', 'son#0']));
      expect(withSon.where((k) => k.startsWith('brother')), isEmpty);
    });

    test('a son blocks paternal uncles and cousins', () {
      final keys = seedKeysFor([
        const Heir(HeirRelation.son, 'Son'),
        ...many(HeirRelation.fullUncle, 1),
        ...many(HeirRelation.fullCousin, 1),
      ]);
      expect(keys, ['son#0']);
    });

    test('the father blocks the paternal grandfather', () {
      final keys = seedKeysFor([
        const Heir(HeirRelation.son, 'Son'),
        const Heir(HeirRelation.father, 'Father'),
        const Heir(HeirRelation.grandfather, 'Grandfather'),
      ]);
      expect(keys, containsAll(['son#0', 'father#0']));
      expect(keys.where((k) => k == 'other#0'), isEmpty, reason: 'grandfather is blocked by the father');
    });

    test('the mother blocks the grandmother', () {
      final keys = seedKeysFor([
        const Heir(HeirRelation.son, 'Son'),
        const Heir(HeirRelation.mother, 'Mother'),
        const Heir(HeirRelation.maternalGrandmother, 'Grandmother'),
      ]);
      expect(keys, containsAll(['son#0', 'mother#0']));
      expect(keys.where((k) => k == 'other#0'), isEmpty);
    });

    test('with only daughters the brothers DO inherit, so they are pre-loaded', () {
      // The mirror of the son case — proves the rule tracks the engine rather than a
      // hardcoded "siblings never inherit".
      final keys = seedKeysFor([
        const Heir(HeirRelation.daughter, 'Daughter'),
        ...many(HeirRelation.fullBrother, 1),
      ]);
      expect(keys, containsAll(['daughter#0', 'brother#0']));
    });

    test('an uncle still takes the residue alongside a lone daughter', () {
      final keys = seedKeysFor([
        const Heir(HeirRelation.daughter, 'Daughter'),
        ...many(HeirRelation.fullUncle, 1),
      ]);
      expect(keys, containsAll(['daughter#0', 'other#0']));
    });
  });

  group('heirRowKeys', () {
    test('keys existing rows by relation + position, mirroring the seed keys', () {
      const rows = [
        HeirContact(id: 'a', relation: 'son'),
        HeirContact(id: 'b', relation: 'wife'),
        HeirContact(id: 'c', relation: 'son'),
      ];
      expect(heirRowKeys(rows), {'a': 'son#0', 'b': 'wife#0', 'c': 'son#1'});
    });

    test('a seeded family round-trips: every seed key is matched by its row', () {
      final keys = seedKeysFor([
        ...many(HeirRelation.wife, 2),
        const Heir(HeirRelation.son, 'Son'),
        const Heir(HeirRelation.mother, 'Mother'),
      ]);
      // Rows created in seed order, as _syncSeededHeirs appends them.
      final rows = [
        for (var i = 0; i < keys.length; i++) HeirContact(id: 'row$i', relation: keys[i].split('#').first),
      ];
      expect(heirRowKeys(rows).values.toSet(), keys.toSet());
    });
  });
}
