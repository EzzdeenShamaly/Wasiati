import { validateHeirSet } from './heir-validation';

/**
 * Impossible families must be REFUSED, not quietly repaired.
 *
 * The engine merges duplicate relations, which is correct for its own purposes — a father can
 * hold a fixed sixth AND the residue, and those entries must combine. But it meant a caller
 * sending two fathers got one father back and a will that still certified "100%", with the
 * second entry gone from a document the owner would sign. For a sealed instrument that is the
 * worst failure shape available: it looks complete, and what vanished is a person the owner
 * named.
 */
describe('heir-set validation', () => {
  const h = (relation: string, name = relation) => ({ relation, name });

  it('accepts an ordinary family', () => {
    expect(validateHeirSet([h('WIFE'), h('SON', 'S1'), h('SON', 'S2'), h('DAUGHTER'), h('MOTHER')])).toEqual([]);
  });

  for (const rel of ['FATHER', 'MOTHER', 'HUSBAND', 'GRANDFATHER', 'PATERNAL_GRANDMOTHER', 'MATERNAL_GRANDMOTHER']) {
    it(`refuses two of ${rel}`, () => {
      const errors = validateHeirSet([h(rel, 'a'), h(rel, 'b')]);
      expect(errors).toHaveLength(1);
      expect(errors[0]).toMatch(/only have one/i);
    });
  }

  it('names the relation in the message, so the owner knows which entry to fix', () => {
    expect(validateHeirSet([h('FATHER', 'a'), h('FATHER', 'b')])[0]).toContain('father');
  });

  describe('wives are a limit, not a singleton', () => {
    // Capping wives at one would reject a lawful family — they share the one spouse portion
    // between them, which is why this rule is different from every other.
    for (const n of [1, 2, 3, 4]) {
      it(`accepts ${n} wives`, () => {
        expect(validateHeirSet(Array.from({ length: n }, (_, i) => h('WIFE', `W${i}`)))).toEqual([]);
      });
    }

    it('refuses five', () => {
      const errors = validateHeirSet(Array.from({ length: 5 }, (_, i) => h('WIFE', `W${i}`)));
      expect(errors).toHaveLength(1);
      expect(errors[0]).toMatch(/at most 4 wives/i);
    });
  });

  it('refuses a husband AND a wife — one person cannot leave both', () => {
    // Not a duplicate, but equally impossible. Without this the engine quietly splits the
    // spouse share between them.
    expect(validateHeirSet([h('HUSBAND'), h('WIFE')])[0]).toMatch(/either a husband or a wife/i);
  });

  it('refuses the same maternal grandmother listed under both spellings', () => {
    // 'GRANDMOTHER' is a legacy alias for the maternal one — accepting both seats her twice
    // and pays her twice.
    expect(validateHeirSet([h('GRANDMOTHER'), h('MATERNAL_GRANDMOTHER')])[0]).toMatch(/listed twice/i);
  });

  it('accepts the two grandmothers together — they are different women', () => {
    expect(validateHeirSet([h('PATERNAL_GRANDMOTHER'), h('MATERNAL_GRANDMOTHER')])).toEqual([]);
  });

  it('reports every problem at once rather than one per round trip', () => {
    const errors = validateHeirSet([h('FATHER', 'a'), h('FATHER', 'b'), h('MOTHER', 'c'), h('MOTHER', 'd')]);
    expect(errors).toHaveLength(2);
  });

  it('places no limit on children or siblings', () => {
    const many = Array.from({ length: 12 }, (_, i) => h('SON', `S${i}`));
    expect(validateHeirSet(many)).toEqual([]);
  });

  it('accepts an empty set — that is the engine\'s problem, not a malformed family', () => {
    expect(validateHeirSet([])).toEqual([]);
  });
});
