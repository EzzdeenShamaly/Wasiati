import { shareBasis } from './share-basis';

const RELATIONS = [
  'HUSBAND', 'WIFE', 'MOTHER', 'FATHER', 'GRANDFATHER', 'GRANDMOTHER', 'PATERNAL_GRANDMOTHER',
  'MATERNAL_GRANDMOTHER', 'SON', 'DAUGHTER', 'SON_SON', 'SON_DAUGHTER', 'FULL_SISTER', 'FULL_BROTHER',
  'CONSANGUINE_SISTER', 'CONSANGUINE_BROTHER', 'MATERNAL_SIBLING', 'FULL_NEPHEW', 'FULL_UNCLE',
  'CONSANGUINE_COUSIN', 'BAYT_AL_MAL', 'UNKNOWN',
];

describe('shareBasis', () => {
  it('cites the correct Qur’anic source per heir type', () => {
    expect(shareBasis('HUSBAND').en).toContain('4:12');
    expect(shareBasis('WIFE').en).toContain('4:12');
    expect(shareBasis('MOTHER').en).toContain('4:11');
    expect(shareBasis('FATHER').en).toContain('4:11');
    expect(shareBasis('SON').en).toContain('4:11');
    expect(shareBasis('DAUGHTER').en).toContain('4:11');
    expect(shareBasis('FULL_SISTER').en).toContain('4:176');
    expect(shareBasis('CONSANGUINE_SISTER').en).toContain('4:176');
    expect(shareBasis('MATERNAL_SIBLING').en).toContain('4:12'); // uterine
  });

  it('states the RULE (both fractions) rather than a percent-derived single claim', () => {
    // Robust to ʿawl/radd: the mother basis names both ⅓ and ⅙ regardless of the final %.
    expect(shareBasis('MOTHER').en).toContain('one third');
    expect(shareBasis('MOTHER').en).toContain('one sixth');
    // A daughter's basis covers alone / shared / residue — never asserts a single case.
    expect(shareBasis('DAUGHTER').en).toContain('one half');
    expect(shareBasis('DAUGHTER').en).toContain('two thirds');
    expect(shareBasis('DAUGHTER').en.toLowerCase()).toContain('residue');
  });

  it('agnates and grandmothers cite residue / Sunnah', () => {
    expect(shareBasis('FULL_BROTHER').en.toLowerCase()).toContain('residue');
    expect(shareBasis('FULL_UNCLE').en.toLowerCase()).toContain('agnate');
    expect(shareBasis('GRANDMOTHER').en).toContain('Sunnah');
    expect(shareBasis('BAYT_AL_MAL').en).toMatch(/treasury/i);
  });

  it('every relation returns a non-empty EN + AR basis', () => {
    for (const rel of RELATIONS) {
      const b = shareBasis(rel);
      expect(b.en.length).toBeGreaterThan(0);
      expect(b.ar.length).toBeGreaterThan(0);
    }
  });
});
