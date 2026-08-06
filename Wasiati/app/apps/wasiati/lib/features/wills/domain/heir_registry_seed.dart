// Which heirs the create-flow heir registry (step 2) pre-loads.
//
// The registry is "who to reach at claim time", so it must list exactly the people
// who actually inherit — and nobody who doesn't. Rather than re-deriving hijab here
// (the fara'id engine already models it, and it is verified), the qualification test
// IS the engine's own output: seed one row per heir the live share preview awards a
// non-zero share to. An heir blocked by hijab — brothers once a son exists, the
// paternal grandfather while the father is alive — never appears in that result, so
// it is never seeded, for free and by construction.

import 'wills_models.dart';

/// A registry row the fara'id result calls for. [key] is stable across re-entry
/// ('son#0', 'wife#1'): the relation plus the heir's index within that relation.
class HeirSeed {
  final String key;
  final String relation;
  const HeirSeed(this.key, this.relation);

  @override
  bool operator ==(Object other) => other is HeirSeed && other.key == key && other.relation == relation;
  @override
  int get hashCode => Object.hash(key, relation);
  @override
  String toString() => 'HeirSeed($key)';
}

/// The heir-registry relation key for a fara'id relation, or null when the entry is
/// not a person to contact.
///
/// The registry roster is the prototype's human relations (HEIR_CONTACT_RELATIONS
/// server-side: wife/husband/son/daughter/mother/father/brother/sister/other), which
/// is coarser than the fara'id enum — so the distant agnates the engine can award a
/// residue to (grandparents, uncles, nephews, cousins) land on 'other'. Uterine
/// siblings map to 'other' too: MATERNAL_SIBLING carries no gender, and guessing one
/// would put a wrong label on a real person.
///
/// Bayt al-mal returns null. It is the public treasury taking an unclaimed surplus,
/// not an heir with a phone number.
String? registryRelationFor(String faraidRelation) => switch (faraidRelation) {
      'WIFE' => 'wife',
      'HUSBAND' => 'husband',
      'SON' || 'SON_SON' => 'son',
      'DAUGHTER' || 'SON_DAUGHTER' => 'daughter',
      'MOTHER' => 'mother',
      'FATHER' => 'father',
      'FULL_BROTHER' || 'CONSANGUINE_BROTHER' => 'brother',
      'FULL_SISTER' || 'CONSANGUINE_SISTER' => 'sister',
      kBaytAlMal => null,
      _ => 'other',
    };

/// The registry rows [shares] calls for, in engine order — one per heir with a
/// non-zero share, keyed 'relation#indexWithinRelation'.
List<HeirSeed> qualifyingHeirSeeds(List<ShariaShare> shares) {
  final seen = <String, int>{};
  final out = <HeirSeed>[];
  for (final s in shares) {
    if (s.sharePercent <= 0) continue;
    final rel = registryRelationFor(s.heirRelation);
    if (rel == null) continue;
    final i = seen.update(rel, (v) => v + 1, ifAbsent: () => 0);
    out.add(HeirSeed('$rel#$i', rel));
  }
  return out;
}

/// The key each existing registry row occupies — the same relation+index scheme as
/// [qualifyingHeirSeeds], taken in list order (the API returns rows createdAt-ascending).
/// Returned as contactId -> key.
Map<String, String> heirRowKeys(List<HeirContact> rows) {
  final seen = <String, int>{};
  return {
    for (final c in rows) c.id: '${c.relation}#${seen.update(c.relation, (v) => v + 1, ifAbsent: () => 0)}',
  };
}
