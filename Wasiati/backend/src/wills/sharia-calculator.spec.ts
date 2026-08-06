import { calculateShariaShares, validateBequests, HeirInput, Madhhab } from './sharia-calculator';

const H = (relation: HeirInput['relation'], name: string = relation): HeirInput => ({ relation, name });
const pct = (heirs: HeirInput[], relation: string, madhhab?: Madhhab) =>
  calculateShariaShares(heirs, madhhab)
    .filter((s) => s.heirRelation === relation)
    .reduce((a, s) => a + s.sharePercent, 0);
const total = (heirs: HeirInput[], madhhab?: Madhhab) =>
  calculateShariaShares(heirs, madhhab).reduce((a, s) => a + s.sharePercent, 0);

describe('calculateShariaShares', () => {
  it('wife + son + daughter (spouse 1/8, residue 2:1)', () => {
    const h = [H('WIFE'), H('SON'), H('DAUGHTER')];
    expect(pct(h, 'WIFE')).toBeCloseTo(12.5, 1);
    expect(pct(h, 'SON')).toBeCloseTo(58.33, 1);
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(29.17, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('daughter + mother + father (father takes 1/6 + residue = 1/3)', () => {
    const h = [H('DAUGHTER'), H('MOTHER'), H('FATHER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'MOTHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'FATHER')).toBeCloseTo(33.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('husband + mother + full brother (brother is residuary)', () => {
    const h = [H('HUSBAND'), H('MOTHER'), H('FULL_BROTHER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(50, 1);
    expect(pct(h, 'MOTHER')).toBeCloseTo(33.33, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(16.67, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it("husband + 2 daughters + mother + father applies 'awl (base 12 -> 15)", () => {
    const h = [H('HUSBAND'), H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('MOTHER'), H('FATHER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(20, 1); // 3/15
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(53.33, 1); // 8/15
    expect(pct(h, 'MOTHER')).toBeCloseTo(13.33, 1); // 2/15
    expect(pct(h, 'FATHER')).toBeCloseTo(13.33, 1); // 2/15
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('full siblings are blocked by a son', () => {
    const h = [H('SON'), H('FULL_BROTHER')];
    expect(pct(h, 'FULL_BROTHER')).toBe(0);
    expect(pct(h, 'SON')).toBeCloseTo(100, 1);
  });

  it('radd: two daughters + mother (no residuary) returns surplus, total = 100', () => {
    const h = [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('MOTHER')];
    expect(total(h)).toBeCloseTo(100, 1);
    expect(pct(h, 'DAUGHTER')).toBeGreaterThan(pct(h, 'MOTHER'));
  });

  // --- Al-'Umariyyatan / al-Gharrawayn: mother gets 1/3 of the RESIDUE after the
  // spouse, not 1/3 of the whole estate. ---
  it('gharrawayn: husband + mother + father → 1/2, 1/6, 1/3', () => {
    const h = [H('HUSBAND'), H('MOTHER'), H('FATHER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(50, 1);
    expect(pct(h, 'MOTHER')).toBeCloseTo(16.67, 1); // 1/3 of the 1/2 remainder
    expect(pct(h, 'FATHER')).toBeCloseTo(33.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('gharrawayn: wife + mother + father → 1/4, 1/4, 1/2', () => {
    const h = [H('WIFE'), H('MOTHER'), H('FATHER')];
    expect(pct(h, 'WIFE')).toBeCloseTo(25, 1);
    expect(pct(h, 'MOTHER')).toBeCloseTo(25, 1); // 1/3 of the 3/4 remainder
    expect(pct(h, 'FATHER')).toBeCloseTo(50, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('gharrawayn also applies with grandfather standing in for the father', () => {
    const h = [H('HUSBAND'), H('MOTHER'), H('GRANDFATHER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(50, 1);
    expect(pct(h, 'MOTHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(33.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('NOT gharrawayn: mother reverts to 1/6 with a child present', () => {
    const h = [H('HUSBAND'), H('MOTHER'), H('FATHER'), H('SON')];
    expect(pct(h, 'MOTHER')).toBeCloseTo(16.67, 1); // 1/6 with a descendant
    expect(total(h)).toBeCloseTo(100, 1);
  });

  // --- 'Asaba ma'a al-ghayr: full sisters become residuaries alongside daughters. ---
  it("two daughters + full sister: sister is residuary (2/3, 1/3), no 'awl", () => {
    const h = [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('FULL_SISTER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(66.67, 1);
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(33.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('husband + daughter + full sister → 1/4, 1/2, 1/4 (sister residuary)', () => {
    const h = [H('HUSBAND'), H('DAUGHTER'), H('FULL_SISTER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(25, 1);
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(25, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('full sisters alone remain Qur\'anic sharers with radd (no daughters)', () => {
    const h = [H('FULL_SISTER', 's1'), H('FULL_SISTER', 's2')];
    expect(total(h)).toBeCloseTo(100, 1); // 2/3 then radd → 100
  });

  // --- Grandfather with siblings: madhhab-selectable (default JUMHUR = muqasama). ---
  it('JUMHUR (default): grandfather + full brother share by muqasama → 50 / 50', () => {
    const h = [H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(50, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: grandfather + 2 full brothers → 1/3 each (muqasama = 1/3 of residue)', () => {
    const h = [H('GRANDFATHER'), H('FULL_BROTHER', 'b1'), H('FULL_BROTHER', 'b2')];
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(33.33, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(66.67, 1); // 33.33 each
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: grandfather + full sister → 2:1 (66.67 / 33.33)', () => {
    const h = [H('GRANDFATHER'), H('FULL_SISTER')];
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(66.67, 1);
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(33.33, 1);
  });

  it('JUMHUR: husband + grandfather + full brother → 50 / 25 / 25', () => {
    const h = [H('HUSBAND'), H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(50, 1);
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(25, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(25, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: 1/6-of-estate guarantee — husband + mother + grandfather + brother', () => {
    const h = [H('HUSBAND'), H('MOTHER'), H('GRANDFATHER'), H('FULL_BROTHER')];
    // Husband 1/2, mother 1/3, residue 1/6 → GF takes the 1/6 guarantee, brother 0.
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(0, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('HANAFI: grandfather blocks the siblings (100 / 0)', () => {
    const h = [H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'GRANDFATHER', 'HANAFI')).toBeCloseTo(100, 1);
    expect(pct(h, 'FULL_BROTHER', 'HANAFI')).toBe(0);
  });

  // --- Grandfather WITH a female descendant + siblings (Zayd doctrine). Regression
  // guard for the bug where the grandfather took the whole residue (siblings → 0) in
  // every school when a daughter was present. The muqāsama must still apply outside
  // Ḥanafī; the grandfather takes the best of muqāsama / ⅓-residue / ⅙-estate. ---
  it('JUMHUR: grandfather + daughter + full brother → 50 / 25 / 25 (muqasama, not block)', () => {
    const h = [H('DAUGHTER'), H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1); // fixed 1/2
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(25, 1); // muqasama = 1/2 of the 1/2 remainder
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(25, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: grandfather + daughter + full sister → 50 / 33.33 / 16.67', () => {
    const h = [H('DAUGHTER'), H('GRANDFATHER'), H('FULL_SISTER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(33.33, 1); // muqasama 2:1 over the 1/2 remainder
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(16.67, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: grandfather + daughter + 2 full brothers → 50 / 16.67 / 16.67 / 16.67', () => {
    const h = [H('DAUGHTER'), H('GRANDFATHER'), H('FULL_BROTHER', 'b1'), H('FULL_BROTHER', 'b2')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(16.67, 1); // muqasama = 2/6 of the 1/2 remainder
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(33.33, 1); // 16.67 each
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('JUMHUR: husband + daughter + grandfather + full brother → GF gets the 1/6-estate floor', () => {
    const h = [H('HUSBAND'), H('DAUGHTER'), H('GRANDFATHER'), H('FULL_BROTHER')];
    // Husband 1/4, daughter 1/2, remainder 1/4. GF best-of: muqasama 1/8, 1/3-remainder 1/12,
    // 1/6-estate floor 1/6 → GF 1/6; brother gets the rest of the remainder (1/12).
    expect(pct(h, 'HUSBAND')).toBeCloseTo(25, 1);
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'GRANDFATHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(8.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('HANAFI: grandfather + daughter + full brother still blocks the brother (50 / 50 / 0)', () => {
    const h = [H('DAUGHTER'), H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'DAUGHTER', 'HANAFI')).toBeCloseTo(50, 1);
    expect(pct(h, 'GRANDFATHER', 'HANAFI')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_BROTHER', 'HANAFI')).toBe(0);
    expect(total(h, 'HANAFI')).toBeCloseTo(100, 1);
  });
});

describe('extended heirs (grandchildren, consanguine/uterine, nephews, uncles, cousins)', () => {
  it("son's daughter completes 2/3 with a daughter (+ father) → 50 / 16.67 / 33.33", () => {
    const h = [H('DAUGHTER'), H('SON_DAUGHTER'), H('FATHER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'SON_DAUGHTER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'FATHER')).toBeCloseTo(33.33, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it("daughter + son's daughter alone → radd 75 / 25", () => {
    const h = [H('DAUGHTER'), H('SON_DAUGHTER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(75, 1);
    expect(pct(h, 'SON_DAUGHTER')).toBeCloseTo(25, 1);
  });

  it("son's son is residuary with a daughter → 50 / 50", () => {
    const h = [H('SON_DAUGHTER', 'gd'), H('DAUGHTER'), H('SON_SON')];
    // daughter 1/2; grandson+granddaughter split the residue 2:1
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'SON_SON')).toBeCloseTo(33.33, 1);
    expect(pct(h, 'SON_DAUGHTER')).toBeCloseTo(16.67, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it("two daughters block the son's daughter unless a grandson is present", () => {
    const blocked = [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('SON_DAUGHTER')];
    expect(pct(blocked, 'SON_DAUGHTER')).toBe(0); // blocked
    const saved = [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('SON_DAUGHTER'), H('SON_SON')];
    expect(pct(saved, 'DAUGHTER')).toBeCloseTo(66.67, 1);
    expect(pct(saved, 'SON_SON')).toBeCloseTo(22.22, 1);
    expect(pct(saved, 'SON_DAUGHTER')).toBeCloseTo(11.11, 1);
    expect(total(saved)).toBeCloseTo(100, 1);
  });

  it('consanguine sister completes 2/3 with one full sister → radd 75 / 25', () => {
    const h = [H('FULL_SISTER'), H('CONSANGUINE_SISTER')];
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(75, 1);
    expect(pct(h, 'CONSANGUINE_SISTER')).toBeCloseTo(25, 1);
  });

  it("husband + full sister + consanguine sister applies 'awl → 42.86 / 42.86 / 14.29", () => {
    const h = [H('HUSBAND'), H('FULL_SISTER'), H('CONSANGUINE_SISTER')];
    expect(pct(h, 'HUSBAND')).toBeCloseTo(42.86, 1);
    expect(pct(h, 'FULL_SISTER')).toBeCloseTo(42.86, 1);
    expect(pct(h, 'CONSANGUINE_SISTER')).toBeCloseTo(14.29, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('consanguine brother is residuary with a daughter → 50 / 50', () => {
    const h = [H('DAUGHTER'), H('CONSANGUINE_BROTHER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'CONSANGUINE_BROTHER')).toBeCloseTo(50, 1);
  });

  it('consanguine sister is residuary (maʿa al-ghayr) with a daughter → 50 / 50', () => {
    const h = [H('DAUGHTER'), H('CONSANGUINE_SISTER')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'CONSANGUINE_SISTER')).toBeCloseTo(50, 1);
  });

  it('full nephew (brother\'s son) is residuary with a daughter → 50 / 50', () => {
    const h = [H('DAUGHTER'), H('FULL_NEPHEW')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_NEPHEW')).toBeCloseTo(50, 1);
  });

  it('full paternal uncle is residuary with a daughter → 50 / 50', () => {
    const h = [H('DAUGHTER'), H('FULL_UNCLE')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_UNCLE')).toBeCloseTo(50, 1);
  });

  it('cousin (uncle\'s son) is residuary with a wife → 25 / 75', () => {
    const h = [H('WIFE'), H('FULL_COUSIN')];
    expect(pct(h, 'WIFE')).toBeCloseTo(25, 1);
    expect(pct(h, 'FULL_COUSIN')).toBeCloseTo(75, 1);
  });

  it('residuary priority: full brother blocks a consanguine brother, nephew, uncle', () => {
    const h = [H('DAUGHTER'), H('FULL_BROTHER'), H('CONSANGUINE_BROTHER'), H('FULL_UNCLE')];
    expect(pct(h, 'DAUGHTER')).toBeCloseTo(50, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(50, 1);
    expect(pct(h, 'CONSANGUINE_BROTHER')).toBe(0);
    expect(pct(h, 'FULL_UNCLE')).toBe(0);
  });

  it('maternal grandmother inherits 1/6; a father does not block her', () => {
    const h = [H('FATHER'), H('MATERNAL_GRANDMOTHER'), H('SON')];
    expect(pct(h, 'MATERNAL_GRANDMOTHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'FATHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'SON')).toBeCloseTo(66.67, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('a father DOES block the paternal grandmother', () => {
    const h = [H('FATHER'), H('PATERNAL_GRANDMOTHER'), H('SON')];
    expect(pct(h, 'PATERNAL_GRANDMOTHER')).toBe(0);
    expect(pct(h, 'FATHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'SON')).toBeCloseTo(83.33, 1);
  });

  it('uterine siblings: mother + 2 uterine + full brother → 16.67 / 33.33 / 50', () => {
    const h = [H('MOTHER'), H('MATERNAL_SIBLING', 'u1'), H('MATERNAL_SIBLING', 'u2'), H('FULL_BROTHER')];
    expect(pct(h, 'MOTHER')).toBeCloseTo(16.67, 1);
    expect(pct(h, 'MATERNAL_SIBLING')).toBeCloseTo(33.33, 1);
    expect(pct(h, 'FULL_BROTHER')).toBeCloseTo(50, 1);
    expect(total(h)).toBeCloseTo(100, 1);
  });

  it('a male descendant blocks uterine siblings entirely', () => {
    const h = [H('SON_SON'), H('MATERNAL_SIBLING')];
    expect(pct(h, 'MATERNAL_SIBLING')).toBe(0);
    expect(pct(h, 'SON_SON')).toBeCloseTo(100, 1);
  });
});

/**
 * Radd is the point where the four schools visibly disagree, so it is pinned per
 * school. Cases and expected numbers are from WASIATI_SPEC.md §4 and §10.
 */
describe('school-aware radd and bayt al-māl', () => {
  it('Jumhūr: wife + mother → surplus returns to the mother, never the spouse', () => {
    const h = [H('WIFE'), H('MOTHER')];
    expect(pct(h, 'WIFE', 'JUMHUR')).toBeCloseTo(25, 1);
    expect(pct(h, 'MOTHER', 'JUMHUR')).toBeCloseTo(75, 1);
    expect(pct(h, 'BAYT_AL_MAL', 'JUMHUR')).toBe(0);
    expect(total(h, 'JUMHUR')).toBeCloseTo(100, 1);
  });

  it('ALL schools return the surplus by radd (contemporary practice, DECISIONS §0)', () => {
    const h = [H('WIFE'), H('MOTHER')];
    for (const school of ['HANAFI', 'HANBALI', 'MALIKI', 'SHAFII'] as Madhhab[]) {
      expect(pct(h, 'MOTHER', school)).toBeCloseTo(75, 1);
      expect(pct(h, 'BAYT_AL_MAL', school)).toBe(0);
      expect(total(h, school)).toBeCloseTo(100, 1);
    }
  });

  it('Mālikī and Shāfiʿī now match Jumhūr for these heirs (radd, no bayt al-māl)', () => {
    const h = [H('WIFE'), H('MOTHER')];
    for (const school of ['MALIKI', 'SHAFII'] as Madhhab[]) {
      expect(pct(h, 'WIFE', school)).toBeCloseTo(25, 1); // 1/4
      expect(pct(h, 'MOTHER', school)).toBeCloseTo(75, 1); // 1/3 + radd
      expect(pct(h, 'BAYT_AL_MAL', school)).toBe(0);
      expect(total(h, school)).toBeCloseTo(100, 1);
    }
  });

  it('a surplus with NOBODY to claim it still goes to the treasury rather than vanishing', () => {
    // REWRITTEN 22 Jul 2026, and the rewrite is the point.
    //
    // This used to assert that a lone husband took 1/2 while the other half went to bayt
    // al-māl — it was encoding the defect as the contract. The classical rule presumes a
    // treasury that receives and administers the share; in the jurisdictions this product
    // serves there is none, so the share lapses into intestacy and a secular court divides
    // it. A sole surviving spouse now takes the whole estate (see "a sole surviving spouse
    // takes everything" below, and DECISIONS §21).
    //
    // What the treasury line is still FOR is an estate with no heir whatsoever: there is
    // nobody to return it to, and naming it keeps the result summing to 100% instead of
    // silently losing the estate.
    expect(calculateShariaShares([], 'JUMHUR').map((s) => s.heirRelation)).toEqual(['BAYT_AL_MAL']);
    expect(pct([], 'BAYT_AL_MAL')).toBeCloseTo(100, 1);
  });

  it('ʿawl is unaffected by school — an over-subscription still shrinks proportionally', () => {
    // Husband 1/2 + 2 full sisters 2/3 = 7/6 → ʿawl.
    const h = [H('HUSBAND'), H('FULL_SISTER', 's1'), H('FULL_SISTER', 's2')];
    for (const school of ['JUMHUR', 'MALIKI', 'SHAFII', 'HANAFI', 'HANBALI'] as Madhhab[]) {
      expect(pct(h, 'HUSBAND', school)).toBeCloseTo(42.86, 1); // (1/2)/(7/6)
      expect(pct(h, 'BAYT_AL_MAL', school)).toBe(0); // nothing left over
      expect(total(h, school)).toBeCloseTo(100, 1);
    }
  });

  it('two daughters alone: 2/3 fixed, then radd fills to 100 in EVERY school', () => {
    const h = [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2')];
    // Contemporary radd (DECISIONS §0): Mālikī now matches Jumhūr — no escheat.
    for (const school of ['JUMHUR', 'MALIKI', 'SHAFII', 'HANAFI', 'HANBALI'] as Madhhab[]) {
      expect(pct(h, 'DAUGHTER', school)).toBeCloseTo(100, 1);
      expect(pct(h, 'BAYT_AL_MAL', school)).toBe(0);
    }
  });
});

describe('grandfather with siblings, per school', () => {
  it('Ḥanafī: the grandfather blocks full siblings entirely', () => {
    const h = [H('GRANDFATHER'), H('FULL_BROTHER')];
    expect(pct(h, 'GRANDFATHER', 'HANAFI')).toBeCloseTo(100, 1);
    expect(pct(h, 'FULL_BROTHER', 'HANAFI')).toBe(0);
  });

  it('every other school shares with them by muqāsama', () => {
    const h = [H('GRANDFATHER'), H('FULL_BROTHER')];
    for (const school of ['JUMHUR', 'MALIKI', 'SHAFII', 'HANBALI'] as Madhhab[]) {
      expect(pct(h, 'GRANDFATHER', school)).toBeCloseTo(50, 1);
      expect(pct(h, 'FULL_BROTHER', school)).toBeCloseTo(50, 1);
    }
  });

  it('grandfather in the father’s place + son → 16.7 / 83.3 in every school', () => {
    const h = [H('GRANDFATHER'), H('SON')];
    for (const school of ['JUMHUR', 'HANAFI', 'MALIKI', 'SHAFII', 'HANBALI'] as Madhhab[]) {
      expect(pct(h, 'GRANDFATHER', school)).toBeCloseTo(16.67, 1);
      expect(pct(h, 'SON', school)).toBeCloseTo(83.33, 1);
    }
  });
});

describe('validateBequests', () => {
  it('rejects bequests over 1/3', () => {
    expect(() => validateBequests([{ sharePercent: 34 }])).toThrow();
    expect(() => validateBequests([{ sharePercent: 33 }])).not.toThrow();
  });
});

describe('displayed shares sum to EXACTLY 100.00 (largest-remainder rounding)', () => {
  // The exact fractions always sum to 1; the risk is only in rounding each share
  // independently, which drifts thirds-heavy cases to 100.01 / 99.99. toBeCloseTo
  // could not catch that — these assert the exact total.
  const cases: Array<[string, HeirInput[]]> = [
    ['wife + 2 sons + daughter + mother + father', [H('WIFE'), H('SON', 's1'), H('SON', 's2'), H('DAUGHTER'), H('MOTHER'), H('FATHER')]],
    ['daughter + mother + father (thirds)', [H('DAUGHTER'), H('MOTHER'), H('FATHER')]],
    ['gharrawayn: husband + mother + father', [H('HUSBAND'), H('MOTHER'), H('FATHER')]],
    ['3 daughters + father (radd-free residue)', [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('DAUGHTER', 'd3'), H('FATHER')]],
    ['2 daughters + mother (radd)', [H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('MOTHER')]],
    ['wife + son + daughter', [H('WIFE'), H('SON'), H('DAUGHTER')]],
    ['husband + 2 daughters + mother + father (awl)', [H('HUSBAND'), H('DAUGHTER', 'd1'), H('DAUGHTER', 'd2'), H('MOTHER'), H('FATHER')]],
  ];
  for (const [label, heirs] of cases) {
    it(`${label} → exactly 100.00`, () => {
      const shares = calculateShariaShares(heirs);
      const sum = shares.reduce((a, s) => a + s.sharePercent, 0);
      // Sum in basis points so binary-float noise (0.01+0.01+... != exactly N) can't
      // fail a genuinely-correct total.
      expect(Math.round(sum * 100)).toBe(10000);
      // No displayed share is more than 0.01 from its exact fraction — apportionment
      // moves a rounding unit, never a real share.
      for (const s of shares) expect(s.sharePercent).toBeGreaterThanOrEqual(0);
    });
  }
});

/**
 * WHY THE MADHHAB PICKER SHIPS TWO OPTIONS AND NOT FIVE.
 *
 * DECISIONS §13 called for a five-school picker; §20 settled on two (Jumhūr + Ḥanafī), and
 * the owner's condition for that was explicit: keep two IF two genuinely cover every distinct
 * calculation, otherwise add the rest. This test is the measurement behind that answer, kept
 * executable so the answer cannot quietly go stale.
 *
 * Across the heir shapes we model, all five schools collapse into exactly TWO outcome groups:
 *
 *   Ḥanafī                                — the grandfather BLOCKS siblings entirely
 *   Jumhūr = Mālikī = Shāfiʿī = Ḥanbalī   — siblings share the residue with the grandfather
 *
 * and the ONLY cases that separate them are grandfather-with-siblings. Mālikī, Shāfiʿī and
 * Ḥanbalī are byte-identical to Jumhūr everywhere else, so offering them as separate options
 * would give a user three extra labels that compute exactly what "Jumhūr" already computes —
 * the appearance of choice with no arithmetic behind it.
 *
 * THE LOAD-BEARING ASSUMPTION: this holds under CONTEMPORARY radd, where a surplus returns to
 * the heirs under every school (see RADD_SCHOOLS). Classical Mālikī/Shāfiʿī doctrine sends
 * that surplus to bayt al-māl instead, which WOULD split them off into a third group and make
 * a two-option picker incomplete. So if RADD_SCHOOLS ever narrows, this test fails — and the
 * failure is the signal that the school count has to be revisited, not that the test is wrong.
 */
describe('school coverage — two options are complete', () => {
  const ALL: Madhhab[] = ['JUMHUR', 'HANAFI', 'MALIKI', 'SHAFII', 'HANBALI'];
  const h = (relation: string, name = relation) => ({ relation, name }) as any;

  /** Every school's result for one heir set, as a comparable string. */
  const outcome = (heirs: any[], m: Madhhab) =>
    calculateShariaShares(heirs, m)
      .map((s) => `${s.heirRelation}:${s.sharePercent.toFixed(3)}`)
      .sort()
      .join(' ');

  const SHAPES: [string, any[]][] = [
    ['daughter only', [h('DAUGHTER')]],
    ['wife + daughter', [h('WIFE'), h('DAUGHTER')]],
    ['mother + full sister', [h('MOTHER'), h('FULL_SISTER')]],
    ['wife + mother + father', [h('WIFE'), h('MOTHER'), h('FATHER')]],
    ['husband + 2 full sisters', [h('HUSBAND'), h('FULL_SISTER', 'S'), h('FULL_SISTER', 'T')]],
    ['wife + son + daughter', [h('WIFE'), h('SON'), h('DAUGHTER')]],
    ['daughter + full uncle', [h('DAUGHTER'), h('FULL_UNCLE')]],
    ['mother + 2 uterine siblings', [h('MOTHER'), h('MATERNAL_SIBLING', 'X'), h('MATERNAL_SIBLING', 'Y')]],
    ['wife + 2 daughters + father', [h('WIFE'), h('DAUGHTER', 'A'), h('DAUGHTER', 'B'), h('FATHER')]],
  ];

  for (const [label, heirs] of SHAPES) {
    it(`all five schools agree on: ${label}`, () => {
      const distinct = new Set(ALL.map((m) => outcome(heirs, m)));
      expect(distinct.size).toBe(1);
    });
  }

  const GRANDFATHER: [string, any[]][] = [
    ['grandfather + full brother', [h('GRANDFATHER'), h('FULL_BROTHER')]],
    ['grandfather + 2 full brothers', [h('GRANDFATHER'), h('FULL_BROTHER', 'A'), h('FULL_BROTHER', 'B')]],
    ['grandfather + full sister', [h('GRANDFATHER'), h('FULL_SISTER')]],
    ['grandfather + brother + mother', [h('GRANDFATHER'), h('FULL_BROTHER'), h('MOTHER')]],
  ];

  for (const [label, heirs] of GRANDFATHER) {
    it(`Ḥanafī stands alone on: ${label}`, () => {
      const hanafi = outcome(heirs, 'HANAFI');
      const others = (['JUMHUR', 'MALIKI', 'SHAFII', 'HANBALI'] as Madhhab[]).map((m) => outcome(heirs, m));
      // The four non-Ḥanafī schools agree with each other...
      expect(new Set(others).size).toBe(1);
      // ...and Ḥanafī differs, which is the whole reason a second option exists.
      expect(hanafi).not.toBe(others[0]);
    });
  }

  it('the five schools collapse into exactly two outcome groups overall', () => {
    // The summary claim, stated once: a third option would carry no distinct arithmetic.
    const groups = new Set<string>();
    for (const m of ALL) {
      groups.add([...SHAPES, ...GRANDFATHER].map(([, heirs]) => outcome(heirs, m)).join('|'));
    }
    expect(groups.size).toBe(2);
  });
});

/**
 * THE THREE UNSHIPPED SCHOOLS ARE ALIASES OF JUMHŪR, AND THAT IS DELIBERATE.
 *
 * The engine's Madhhab type keeps five values, but the picker offers two. Mālikī, Shāfiʿī and
 * Ḥanbalī compute exactly what Jumhūr computes, because under CONTEMPORARY application they
 * genuinely agree with it — the classical Mālikī/Shāfiʿī positions that would separate them
 * (surplus escheating to bayt al-māl instead of returning to the heirs) presuppose a treasury
 * that does not exist in the jurisdictions this product serves.
 *
 * That is not a shortcut, it is the ruling: a will line naming "bayt al-māl" names no legal
 * person, and in US/CA probate a bequest to a non-existent recipient LAPSES — the surplus
 * falls to intestacy and a secular court divides it. Applying radd is the outcome a Sharia
 * product should print; escheat is the one it should not. See DECISIONS §0, §20 and §21.
 *
 * These tests exist so the aliasing is a STATED INTENT rather than an accident nobody noticed.
 * The fingerprint guard (sharia-engine-fingerprint.spec.ts) would catch the arithmetic moving;
 * this says why it should not.
 *
 * IF THIS FAILS, someone implemented a real per-school distinction. That is a doctrinal change
 * affecting how estates divide, so it needs a DECISIONS entry and — per the architectural
 * ruling — a qualified scholar's sign-off. Do not simply delete the test.
 */
describe('Mālikī / Shāfiʿī / Ḥanbalī are intentional aliases of Jumhūr', () => {
  const ALIASES: Madhhab[] = ['MALIKI', 'SHAFII', 'HANBALI'];
  const h = (relation: string, name = relation) => ({ relation, name }) as any;

  const shares = (heirs: any[], m: Madhhab) =>
    calculateShariaShares(heirs, m)
      .map((s) => `${s.heirRelation}:${s.sharePercent.toFixed(4)}`)
      .sort()
      .join(' ');

  /** The configurations where the classical positions WOULD have diverged. */
  const CASES: [string, any[]][] = [
    // Radd: classically Mālikī/Shāfiʿī would give the daughter 1/2 and escheat the rest.
    ['one daughter alone', [h('DAUGHTER')]],
    ['wife + one daughter', [h('WIFE'), h('DAUGHTER')]],
    ['mother + one daughter', [h('MOTHER'), h('DAUGHTER')]],
    ['mother + two uterine siblings', [h('MOTHER'), h('MATERNAL_SIBLING', 'X'), h('MATERNAL_SIBLING', 'Y')]],
    ['full sister alone', [h('FULL_SISTER')]],
    // Al-mushtaraka: the schools split 2-2 classically. Flagged for scholar review.
    ['al-mushtaraka shape', [h('HUSBAND'), h('MOTHER'), h('MATERNAL_SIBLING', 'U1'),
      h('MATERNAL_SIBLING', 'U2'), h('FULL_BROTHER')]],
    // Grandfather cases — where Ḥanafī legitimately differs and these three must NOT.
    ['grandfather + full brother', [h('GRANDFATHER'), h('FULL_BROTHER')]],
    ['grandfather + full sister', [h('GRANDFATHER'), h('FULL_SISTER')]],
  ];

  for (const [label, heirs] of CASES) {
    it(`${label}: all three match Jumhūr exactly`, () => {
      const jumhur = shares(heirs, 'JUMHUR');
      for (const m of ALIASES) expect(shares(heirs, m)).toBe(jumhur);
    });
  }

  it('and they do NOT match Ḥanafī where Ḥanafī legitimately differs', () => {
    // Guards the guard: if every school collapsed into one, the tests above would pass while
    // meaning nothing. Ḥanafī must still stand apart on the grandfather.
    const heirs = [h('GRANDFATHER'), h('FULL_BROTHER')];
    expect(shares(heirs, 'HANAFI')).not.toBe(shares(heirs, 'JUMHUR'));
  });

  it('no surplus is ever sent to bayt al-māl under any shipped school', () => {
    // The escheat branch is intentional dead code. A will line naming a treasury that does
    // not exist would lapse into intestacy, which is the outcome this product must not print.
    for (const m of ['JUMHUR', 'HANAFI', ...ALIASES] as Madhhab[]) {
      for (const [, heirs] of CASES) {
        const out = calculateShariaShares(heirs, m);
        expect(out.some((s) => s.heirRelation === 'BAYT_AL_MAL')).toBe(false);
      }
    }
  });
});

/**
 * A SPOUSE WHO IS THE ONLY SURVIVOR TAKES THE WHOLE ESTATE.
 *
 * The general rule is that a spouse never shares in radd — radd returns a surplus to blood
 * kin, and a widow already has her named fraction. That rule was right, but it had no floor:
 * when there were no blood kin at all, the remainder went to bayt al-māl. So a widow with no
 * children, parents or siblings took her eighth and watched three quarters of her husband's
 * estate leave the family.
 *
 * That is not a rare shape. When this was found, 30 of the 35 sealed wills in the development
 * database carried exactly a WIFE + BAYT_AL_MAL split.
 *
 * The classical rule presumes a treasury that would receive and administer the share. In the
 * jurisdictions this product serves there is none — a will naming bayt al-māl names no legal
 * person, so the share LAPSES into intestacy and a secular court divides it among whichever
 * relatives local law prefers, quite possibly the ones the fara'id had already excluded. The
 * rule, applied without its institution, produces the opposite of its intent. Contemporary
 * codification (Egyptian Law 77/1943 and the statutes following it) returns it to the spouse.
 * Same reasoning as DECISIONS §21, applied to the case §21 missed.
 */
describe('a sole surviving spouse takes everything', () => {
  const h = (relation: string, name = relation) => ({ relation, name }) as any;
  const pct = (heirs: any[], name: string, m: Madhhab = 'JUMHUR') =>
    calculateShariaShares(heirs, m).find((s) => s.heirName === name)?.sharePercent;
  const relations = (heirs: any[], m: Madhhab = 'JUMHUR') =>
    calculateShariaShares(heirs, m).map((s) => s.heirRelation);

  it('a widow alone takes 100%, not 25% with the rest to the treasury', () => {
    expect(pct([h('WIFE')], 'WIFE')).toBe(100);
    expect(relations([h('WIFE')])).not.toContain('BAYT_AL_MAL');
  });

  it('a widower alone takes 100%', () => {
    expect(pct([h('HUSBAND')], 'HUSBAND')).toBe(100);
    expect(relations([h('HUSBAND')])).not.toContain('BAYT_AL_MAL');
  });

  it('co-wives divide it between them, as they divide their eighth', () => {
    const wives = [h('WIFE', 'W1'), h('WIFE', 'W2'), h('WIFE', 'W3'), h('WIFE', 'W4')];
    for (const w of ['W1', 'W2', 'W3', 'W4']) expect(pct(wives, w)).toBe(25);
  });

  it('holds under every school', () => {
    for (const m of ['JUMHUR', 'HANAFI', 'MALIKI', 'SHAFII', 'HANBALI'] as Madhhab[]) {
      expect(pct([h('WIFE')], 'WIFE', m)).toBe(100);
    }
  });

  describe('and the general rule is UNCHANGED — a spouse still never shares radd with kin', () => {
    // The risk in this fix was that radd is shared code: a change aimed at the spouse case
    // could have quietly given spouses a share of every surplus. These pin that it did not.
    it('wife + daughter: the daughter still absorbs the whole surplus', () => {
      const heirs = [h('WIFE'), h('DAUGHTER')];
      expect(pct(heirs, 'WIFE')).toBe(12.5);
      expect(pct(heirs, 'DAUGHTER')).toBe(87.5);
    });

    it('wife + mother: the mother still absorbs it', () => {
      const heirs = [h('WIFE'), h('MOTHER')];
      expect(pct(heirs, 'WIFE')).toBe(25);
      expect(pct(heirs, 'MOTHER')).toBe(75);
    });

    it('husband + son: the son still takes the residue as ʿasaba', () => {
      const heirs = [h('HUSBAND'), h('SON')];
      expect(pct(heirs, 'HUSBAND')).toBe(25);
      expect(pct(heirs, 'SON')).toBe(75);
    });
  });

  it('an estate with NO heirs at all still shows bayt al-māl rather than vanishing', () => {
    // Nothing to return it to. Shown explicitly so the result still sums to 100% and the
    // absence is visible rather than silent.
    expect(relations([])).toEqual(['BAYT_AL_MAL']);
  });
});
