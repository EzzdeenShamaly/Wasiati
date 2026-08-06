import { HeirRelation } from './sharia-calculator';

/**
 * Rejects heir sets that describe a family that cannot exist.
 *
 * The engine merges duplicates, which is right for its own purposes — a father can hold a
 * fixed sixth AND the residue, and those two entries must combine. But it means a caller
 * sending TWO fathers gets one father and a document that still certifies "100%", with the
 * second entry silently gone. For a sealed instrument that is the worst shape of failure:
 * it looks complete, and the thing that vanished is a person the owner named.
 *
 * The create flow itself cannot produce these — it asks about parents and grandparents with
 * on/off toggles — so this guards the API, where a heirs[] array arrives from a client we do
 * not control, and any future importer.
 *
 * Deliberately NOT enforced inside calculateShariaShares: the live preview recomputes on
 * every keystroke and must keep rendering through half-finished input. Refusal belongs at
 * the moment a will is created or sealed, not while someone is typing.
 */

/** Relations of which a person can have exactly one. */
const SINGLETONS: readonly HeirRelation[] = [
  'HUSBAND',
  'FATHER',
  'MOTHER',
  'GRANDFATHER',
  'PATERNAL_GRANDMOTHER',
  'MATERNAL_GRANDMOTHER',
  'GRANDMOTHER',
];

/**
 * A man may be survived by up to four wives, and they share the one spouse portion between
 * them. This is the reason the rule is a LIMIT and not a singleton — capping wives at one
 * would reject a lawful family.
 */
const MAX_WIVES = 4;

export interface HeirLike {
  relation: string;
  name?: string;
}

/** Human-readable reasons, one per problem. Empty means the set is coherent. */
export function validateHeirSet(heirs: readonly HeirLike[]): string[] {
  const errors: string[] = [];
  const count = new Map<string, number>();
  for (const h of heirs) count.set(h.relation, (count.get(h.relation) ?? 0) + 1);

  for (const rel of SINGLETONS) {
    const n = count.get(rel) ?? 0;
    if (n > 1) errors.push(`A person can only have one ${label(rel)} — ${n} were listed.`);
  }

  const wives = count.get('WIFE') ?? 0;
  if (wives > MAX_WIVES) {
    errors.push(`A will can name at most ${MAX_WIVES} wives — ${wives} were listed.`);
  }

  // Not a duplicate, but equally impossible: one person cannot leave both a husband and a
  // wife. Catching it here stops the engine quietly splitting the spouse share between them.
  if ((count.get('HUSBAND') ?? 0) > 0 && wives > 0) {
    errors.push('A will names either a husband or a wife, never both.');
  }

  // The two grandmother spellings are the SAME woman. 'GRANDMOTHER' is a legacy alias for the
  // maternal one, so accepting both would seat her twice and pay her twice.
  if ((count.get('GRANDMOTHER') ?? 0) > 0 && (count.get('MATERNAL_GRANDMOTHER') ?? 0) > 0) {
    errors.push('The maternal grandmother is listed twice.');
  }

  return errors;
}

function label(relation: string): string {
  return relation.toLowerCase().replace(/_/g, ' ');
}
