/**
 * Sharia inheritance (fara'id) share calculator — COMPREHENSIVE engine.
 *
 * Models the full set of primary Sunni heirs (aṣḥāb al-furūḍ + ʿaṣaba):
 *   spouse, sons, daughters, son's sons & daughters (agnatic grandchildren),
 *   father, mother, true paternal grandfather, paternal & maternal grandmothers,
 *   full / consanguine (paternal-half) / uterine (maternal-half) siblings,
 *   full & consanguine brother's sons (nephews), full & consanguine paternal
 *   uncles, and full & consanguine paternal uncles' sons (cousins).
 *
 * Implements the fixed shares (furūḍ), residue by the ʿaṣaba priority chain
 * (bi-nafsihi, bi-ghayrihi at 2:1, and maʿa al-ghayr), the main blocking rules
 * (ḥajb), ʿawl (proportional reduction when fixed shares over-subscribe), and
 * radd (return of surplus to the fixed-sharers, spouse excluded).
 *
 * School-dependent rules (select via `madhhab`):
 *   · Radd — Ḥanafī / Ḥanbalī (and the Jumhūr default) return a surplus to the
 *     non-spouse sharers. Mālikī / Shāfiʿī (classical) do NOT: the surplus goes to
 *     bayt al-māl, the public treasury, which appears as its own line.
 *   · Grandfather with siblings — Ḥanafī: the grandfather blocks them entirely.
 *     All others: muqāsama, the grandfather taking the better of muqāsama or 1/3
 *     of the residue, never below 1/6 of the estate when sharers are present.
 *
 * Special case: al-Gharrāwayn / al-ʿUmariyyatān (spouse + both parents → the mother
 * takes 1/3 of the RESIDUE after the spouse, not 1/3 of the estate).
 *
 * A surplus that no one can take (e.g. only a spouse survives) is assigned to
 * BAYT_AL_MAL rather than dropped, so every result sums to exactly 100%.
 *
 * Under contemporary radd (see RADD_SCHOOLS) only TWO distinct divisions exist across
 * the five accepted `madhhab` values for this heir set: Ḥanafī (grandfather blocks
 * siblings) vs everyone else (Jumhūr = Mālikī = Shāfiʿī = Ḥanbalī). The client's
 * picker offers two options for that reason.
 *
 * NOT modelled — see docs/FIQH_REVIEW.md:
 *   · dhawū al-arḥām (distant kindred — daughter's/sister's children, maternal
 *     uncles), whom Ḥanafī, Ḥanbalī and post-classical Shāfiʿī admit ahead of the
 *     treasury when there is NO fixed-sharer (besides a spouse) and NO ʿaṣaba.
 *   · muʿādda ("counting-in"): consanguine siblings should be counted alongside full
 *     siblings when SIZING the grandfather's muqāsama share, then drop out in favour
 *     of the full siblings. We only count consanguines when no full sibling exists,
 *     which can overstate the grandfather's share in mixed-sibling cases.
 *   · al-Akdariyya, the musharraka/Ḥimāriyya case, and the freed-slave patron (walā',
 *     obsolete).
 *
 * The server output MUST be reviewed and certified by a qualified Sharia board before
 * being relied upon. docs/FIQH_REVIEW.md is the document prepared for that review.
 */

export type Madhhab = 'JUMHUR' | 'HANAFI' | 'MALIKI' | 'SHAFII' | 'HANBALI';

/** The public treasury — takes a surplus no heir is entitled to. Not a person. */
export const BAYT_AL_MAL = 'BAYT_AL_MAL';

/** Schools that return a surplus to the non-spouse sharers instead of the treasury. */
// CONTEMPORARY practice (owner decision, docs/DECISIONS.md §0): ALL schools return a
// surplus to the heirs (radd). Classically Mālikī/Shāfiʿī sent it to bayt al-māl, but
// the majority of contemporary Mālikī/Shāfiʿī scholars — and modern Muslim-state law —
// apply radd. So for the heirs we model, Mālikī/Shāfiʿī are identical to Jumhūr, and
// the only remaining inter-school difference is the grandfather-with-siblings case.
const RADD_SCHOOLS: readonly Madhhab[] = ['JUMHUR', 'HANAFI', 'HANBALI', 'MALIKI', 'SHAFII'];

export type HeirRelation =
  | 'HUSBAND'
  | 'WIFE'
  | 'SON'
  | 'DAUGHTER'
  | 'SON_SON' // agnatic grandson (through a son) — and lower
  | 'SON_DAUGHTER' // agnatic granddaughter (through a son)
  | 'FATHER'
  | 'MOTHER'
  | 'GRANDFATHER' // true paternal grandfather (and above)
  | 'PATERNAL_GRANDMOTHER'
  | 'MATERNAL_GRANDMOTHER'
  | 'GRANDMOTHER' // legacy / unspecified → treated as maternal grandmother
  | 'FULL_BROTHER'
  | 'FULL_SISTER'
  | 'CONSANGUINE_BROTHER' // paternal half-brother
  | 'CONSANGUINE_SISTER' // paternal half-sister
  | 'MATERNAL_SIBLING' // uterine (maternal half) brother or sister
  | 'FULL_NEPHEW' // full brother's son
  | 'CONSANGUINE_NEPHEW' // consanguine brother's son
  | 'FULL_UNCLE' // full paternal uncle
  | 'CONSANGUINE_UNCLE' // consanguine paternal uncle
  | 'FULL_COUSIN' // full paternal uncle's son
  | 'CONSANGUINE_COUSIN'; // consanguine paternal uncle's son

export interface HeirInput {
  relation: HeirRelation;
  name: string;
}

export interface ShariaShareResult {
  heirRelation: string;
  heirName: string;
  sharePercent: number;
}

const MAX_FREE_BEQUEST_PERCENT = 100 / 3;

/**
 * Rounds a set of exact fractions (which sum to 1) to 2-dp percentages that sum to
 * EXACTLY 100.00 — the largest-remainder (Hamilton) method.
 *
 * Rounding each share independently (Math.round per share) can leave the total at
 * 100.01 or 99.99, a drift the spec forbids ("shares total exactly 100%"). The Sharia fractions
 * are NOT touched: this only apportions the final rounding. Every share is floored to
 * a basis point (0.01%), then the leftover basis points are handed to the shares with
 * the largest truncated remainders. No displayed share moves more than 0.01 from its
 * exact value, and the ordering breaks ties by input order so the result is stable.
 */
function apportionPercents(fractions: number[]): number[] {
  // SIX decimal places, not two.
  //
  // This used to work in basis points (0.01%), so a sixth was stored as 16.66 rather than
  // 16.666667 — the share was short by 0.007% of the whole estate, and that is money: about
  // $700 on a $10M estate, per heir, baked into a sealed document. The fractions above are
  // exact; only this final display step was coarse, and it was coarse because the column it
  // is written to was Decimal(5,2). Both are now six places.
  //
  // It also made LEGALLY EQUAL heirs print unequally: two heirs each entitled to 2/13 came
  // out as 15.39 and 15.38, because the leftover basis point has to land somewhere. That is
  // unavoidable in principle — 100 cannot always be split evenly into finite decimals — but
  // at six places the gap is 0.000001% instead of 0.01%, which is a rounding artefact rather
  // than a visible difference between two people with identical entitlements.
  const UNITS = 100_000_000; // 100.000000% in millionths of a percent
  const exact = fractions.map((f) => f * UNITS);
  const floors = exact.map(Math.floor);
  const deficit = UNITS - floors.reduce((s, n) => s + n, 0);
  const byRemainder = exact
    .map((e, i) => ({ i, rem: e - floors[i] }))
    .sort((a, b) => b.rem - a.rem || a.i - b.i);
  const units = [...floors];
  for (let k = 0; k < deficit && k < byRemainder.length; k++) units[byRemainder[k].i] += 1;
  // Round-trip through a fixed string so the result is exactly representable at 6dp and does
  // not reintroduce float dust (0.1 + 0.2 arithmetic) in the value that gets persisted.
  return units.map((n) => Number((n / 1_000_000).toFixed(6)));
}

interface Share {
  relation: string;
  name: string;
  fraction: number; // out of 1
}

export function calculateShariaShares(heirs: HeirInput[], madhhab: Madhhab = 'JUMHUR'): ShariaShareResult[] {
  const grp = (r: HeirRelation) => heirs.filter((h) => h.relation === r);

  const sons = grp('SON');
  const daughters = grp('DAUGHTER');
  const sonSons = grp('SON_SON');
  const sonDaughters = grp('SON_DAUGHTER');
  const husband = grp('HUSBAND')[0];
  const wives = grp('WIFE');
  const father = grp('FATHER')[0];
  const mother = grp('MOTHER')[0];
  const gf0 = grp('GRANDFATHER')[0];
  const patGms = grp('PATERNAL_GRANDMOTHER');
  const matGms = [...grp('MATERNAL_GRANDMOTHER'), ...grp('GRANDMOTHER')]; // legacy → maternal
  const fullBros = grp('FULL_BROTHER');
  const fullSis = grp('FULL_SISTER');
  const conBros = grp('CONSANGUINE_BROTHER');
  const conSis = grp('CONSANGUINE_SISTER');
  const matSibs = grp('MATERNAL_SIBLING');
  const fullNephews = grp('FULL_NEPHEW');
  const conNephews = grp('CONSANGUINE_NEPHEW');
  const fullUncles = grp('FULL_UNCLE');
  const conUncles = grp('CONSANGUINE_UNCLE');
  const fullCousins = grp('FULL_COUSIN');
  const conCousins = grp('CONSANGUINE_COUSIN');

  const hasSon = sons.length > 0;
  const hasSonSon = sonSons.length > 0;
  const maleDesc = hasSon || hasSonSon; // son or agnatic grandson
  const anyDesc = maleDesc || daughters.length > 0 || sonDaughters.length > 0;
  const hasFather = !!father;
  const gf = !hasFather ? gf0 : undefined; // true grandfather substitutes for an absent father
  const fatherLine = hasFather || !!gf;

  const shares: Share[] = [];
  const push = (relation: string, name: string, fraction: number) => {
    if (fraction > 1e-12) shares.push({ relation, name, fraction });
  };
  const sum = () => shares.reduce((s, x) => s + x.fraction, 0);

  // Two-or-more siblings of ANY kind reduce the mother to 1/6, even when blocked.
  const siblingHeadcount =
    fullBros.length + fullSis.length + conBros.length + conSis.length + matSibs.length;

  // al-Gharrāwayn: spouse + mother + father-line only, no descendant, no siblings.
  const spouseFraction = husband ? 1 / 2 : wives.length ? 1 / 4 : 0;
  const gharrawayn = spouseFraction > 0 && !!mother && fatherLine && !anyDesc && siblingHeadcount === 0;

  // --- Spouse ---
  if (husband) push('HUSBAND', husband.name, anyDesc ? 1 / 4 : 1 / 2);
  if (wives.length) {
    const t = anyDesc ? 1 / 8 : 1 / 4;
    wives.forEach((w) => push('WIFE', w.name, t / wives.length));
  }

  // --- Mother / grandmothers ---
  if (mother) {
    const mf = gharrawayn ? (1 - spouseFraction) / 3 : anyDesc || siblingHeadcount >= 2 ? 1 / 6 : 1 / 3;
    push('MOTHER', mother.name, mf);
  } else {
    // Maternal grandmother blocked only by the mother; paternal grandmother blocked
    // by the mother OR the father. Eligible grandmothers share 1/6 equally.
    const gms: { rel: string; name: string }[] = [
      ...matGms.map((g) => ({ rel: 'MATERNAL_GRANDMOTHER', name: g.name })),
      ...(!hasFather ? patGms.map((g) => ({ rel: 'PATERNAL_GRANDMOTHER', name: g.name })) : []),
    ];
    gms.forEach((g) => push(g.rel, g.name, 1 / 6 / gms.length));
  }

  // --- Uterine (maternal) siblings: 1/6 one, 1/3 shared equally (male=female).
  // Blocked by any descendant or any father-line ascendant. ---
  const matSibsActive = !anyDesc && !fatherLine ? matSibs : [];
  if (matSibsActive.length) {
    const t = matSibsActive.length === 1 ? 1 / 6 : 1 / 3;
    matSibsActive.forEach((s) => push('MATERNAL_SIBLING', s.name, t / matSibsActive.length));
  }

  // --- Father / grandfather fixed portion (they also anchor the residue below) ---
  let fatherResiduary = false;
  let gfResiduary = false;
  if (hasFather) {
    if (maleDesc) push('FATHER', father.name, 1 / 6);
    else if (daughters.length || sonDaughters.length) {
      push('FATHER', father.name, 1 / 6);
      fatherResiduary = true;
    } else fatherResiduary = true;
  } else if (gf) {
    // When the grandfather shares the residue with siblings by muqāsama (every school
    // but Ḥanafī), his ENTIRE share is decided by the best-of-three in the residue block
    // below (muqāsama vs 1/3-of-residue vs the 1/6-of-estate floor). Pushing a fixed 1/6
    // here as well would double-count it and wrongly zero out the siblings.
    const gfMuqasamaWithSiblings =
      madhhab !== 'HANAFI' && fullBros.length + fullSis.length + conBros.length + conSis.length > 0;
    if (maleDesc) {
      push('GRANDFATHER', gf.name, 1 / 6); // blocked from residue by a son; siblings also blocked
    } else if (daughters.length || sonDaughters.length) {
      // Like a father, the grandfather takes 1/6 + residue — EXCEPT when muqāsama with
      // siblings applies, where the 1/6 is folded into the best-of-three below.
      if (!gfMuqasamaWithSiblings) push('GRANDFATHER', gf.name, 1 / 6);
      gfResiduary = true;
    } else gfResiduary = true;
  }

  // --- Daughters fixed (only when no son) ---
  if (!hasSon && daughters.length) {
    const t = daughters.length === 1 ? 1 / 2 : 2 / 3;
    daughters.forEach((d) => push('DAUGHTER', d.name, t / daughters.length));
  }

  // --- Son's daughters fixed (no son, and no son's son at their level to make
  // them residuary): alone 1/2 or 2/3; with one daughter 1/6 to complete 2/3;
  // with two+ daughters they are blocked. ---
  if (!hasSon && !hasSonSon && sonDaughters.length) {
    if (daughters.length === 0) {
      const t = sonDaughters.length === 1 ? 1 / 2 : 2 / 3;
      sonDaughters.forEach((d) => push('SON_DAUGHTER', d.name, t / sonDaughters.length));
    } else if (daughters.length === 1) {
      sonDaughters.forEach((d) => push('SON_DAUGHTER', d.name, 1 / 6 / sonDaughters.length));
    }
    // two+ daughters → son's daughters blocked
  }

  const femaleDesc = daughters.length > 0 || sonDaughters.length > 0;

  // Whether full/consanguine sisters act as residuaries (maʿa al-ghayr) alongside
  // a daughter/son's daughter — this happens only when no blocking male exists.
  const fullSisBlocked = maleDesc || hasFather; // grandfather handled via madhhab in residue
  const fullSisMaaAlGhayr = fullSis.length > 0 && !fullSisBlocked && !gf && fullBros.length === 0 && femaleDesc;
  const fullSisIsResiduary =
    fullSis.length > 0 && (fullSisMaaAlGhayr || (!fullSisBlocked && !gf && fullBros.length > 0));

  // Full sisters as FIXED Qur'anic sharers (½ / ⅔) — only when not residuary,
  // no descendant, no father-line.
  if (!fullSisBlocked && !gf && fullBros.length === 0 && !femaleDesc && fullSis.length) {
    const t = fullSis.length === 1 ? 1 / 2 : 2 / 3;
    fullSis.forEach((s) => push('FULL_SISTER', s.name, t / fullSis.length));
  }

  // Consanguine siblings blocked by: male descendant, father, a full brother,
  // full sisters acting as residuary (maʿa al-ghayr / bi-ghayrihi), or two+ full
  // sisters taking ⅔.
  const fullSisTookTwoThirds = !fullSisBlocked && !gf && fullBros.length === 0 && !femaleDesc && fullSis.length >= 2;
  const conBlocked = maleDesc || hasFather || fullBros.length > 0 || fullSisIsResiduary || fullSisTookTwoThirds;
  const conSisMaaAlGhayr = conSis.length > 0 && !conBlocked && !gf && conBros.length === 0 && femaleDesc;
  const conSisIsResiduary =
    conSis.length > 0 && (conSisMaaAlGhayr || (!conBlocked && !gf && conBros.length > 0));

  // Consanguine sisters as FIXED sharers — when not residuary and no descendant:
  //  · one full sister present (took ½): consanguine sisters take 1/6 (complete ⅔)
  //  · no full sister: ½ (one) / ⅔ (2+)
  if (!conBlocked && !gf && conBros.length === 0 && !femaleDesc && conSis.length) {
    const oneFullSisterTookHalf = fullSis.length === 1 && !fullSisBlocked && fullBros.length === 0;
    if (oneFullSisterTookHalf) {
      conSis.forEach((s) => push('CONSANGUINE_SISTER', s.name, 1 / 6 / conSis.length));
    } else if (fullSis.length === 0) {
      const t = conSis.length === 1 ? 1 / 2 : 2 / 3;
      conSis.forEach((s) => push('CONSANGUINE_SISTER', s.name, t / conSis.length));
    }
  }

  // --- Residue (ʿaṣaba) — the single highest-priority agnatic group takes it. ---
  const residue = 1 - sum();
  const distribute = (rs: { relation: string; name: string; units: number }[], amount: number) => {
    const totalUnits = rs.reduce((s, r) => s + r.units, 0);
    if (totalUnits <= 0 || amount <= 1e-12) return;
    rs.forEach((r) => push(r.relation, r.name, amount * (r.units / totalUnits)));
  };
  const asUnits = (list: { name: string }[], relation: string, units: number) =>
    list.map((x) => ({ relation, name: x.name, units }));

  const r = Math.max(0, residue);
  if (hasSon) {
    // Sons (2) + daughters (1) as ʿaṣaba bi-ghayrihi.
    distribute([...asUnits(sons, 'SON', 2), ...asUnits(daughters, 'DAUGHTER', 1)], r);
  } else if (hasSonSon) {
    // Grandsons (2) + granddaughters (1); daughters already took their fixed share.
    distribute([...asUnits(sonSons, 'SON_SON', 2), ...asUnits(sonDaughters, 'SON_DAUGHTER', 1)], r);
  } else if (fatherResiduary && hasFather) {
    push('FATHER', father.name, r);
  } else if (gfResiduary && gf) {
    const gfSibs = [...fullBros, ...fullSis, ...conBros, ...conSis];
    // Ḥanafī: the grandfather blocks siblings outright. Every other school shares
    // with them by muqāsama — including when a daughter/son's-daughter is present
    // (removing the earlier `!femaleDesc` guard, which wrongly gave the grandfather the
    // whole residue and disinherited the siblings in the Jumhūr default).
    if (madhhab !== 'HANAFI' && gfSibs.length > 0) {
      // Majority muqāsama with full (then consanguine) siblings; grandfather takes
      // the better of muqāsama or 1/3 of the residue, never below 1/6 of the estate
      // when other fixed-sharers are present.
      const sibUnits = [
        ...asUnits(fullBros, 'FULL_BROTHER', 2),
        ...asUnits(fullSis, 'FULL_SISTER', 1),
        ...(fullBros.length + fullSis.length === 0
          ? [...asUnits(conBros, 'CONSANGUINE_BROTHER', 2), ...asUnits(conSis, 'CONSANGUINE_SISTER', 1)]
          : []),
      ];
      const units = 2 + sibUnits.reduce((s, x) => s + x.units, 0);
      const muqasama = r * (2 / units);
      const hasFixedSharers = sum() > 1e-9;
      let gfShare = Math.max(muqasama, r / 3);
      if (hasFixedSharers) gfShare = Math.max(gfShare, 1 / 6);
      gfShare = Math.min(gfShare, r);
      push('GRANDFATHER', gf.name, gfShare);
      distribute(sibUnits, Math.max(0, r - gfShare));
    } else {
      push('GRANDFATHER', gf.name, r); // Ḥanafī, or no siblings to share with
    }
  } else if (fullBros.length) {
    distribute([...asUnits(fullBros, 'FULL_BROTHER', 2), ...asUnits(fullSis, 'FULL_SISTER', 1)], r);
  } else if (fullSisIsResiduary && fullSis.length) {
    // Full sisters as ʿaṣaba maʿa al-ghayr — split the remainder equally.
    distribute(asUnits(fullSis, 'FULL_SISTER', 1), r);
  } else if (conBros.length && !conBlocked) {
    distribute([...asUnits(conBros, 'CONSANGUINE_BROTHER', 2), ...asUnits(conSis, 'CONSANGUINE_SISTER', 1)], r);
  } else if (conSisIsResiduary && conSis.length) {
    distribute(asUnits(conSis, 'CONSANGUINE_SISTER', 1), r);
  } else if (fullNephews.length) {
    distribute(asUnits(fullNephews, 'FULL_NEPHEW', 1), r);
  } else if (conNephews.length) {
    distribute(asUnits(conNephews, 'CONSANGUINE_NEPHEW', 1), r);
  } else if (fullUncles.length) {
    distribute(asUnits(fullUncles, 'FULL_UNCLE', 1), r);
  } else if (conUncles.length) {
    distribute(asUnits(conUncles, 'CONSANGUINE_UNCLE', 1), r);
  } else if (fullCousins.length) {
    distribute(asUnits(fullCousins, 'FULL_COUSIN', 1), r);
  } else if (conCousins.length) {
    distribute(asUnits(conCousins, 'CONSANGUINE_COUSIN', 1), r);
  }

  // --- Merge duplicates (e.g. father's fixed 1/6 + residue) ---
  const mergedMap = new Map<string, Share>();
  for (const s of shares) {
    const key = `${s.relation}|${s.name}`;
    const existing = mergedMap.get(key);
    if (existing) existing.fraction += s.fraction;
    else mergedMap.set(key, { ...s });
  }
  const merged = [...mergedMap.values()];

  // --- ʿAwl (over-subscription) and Radd (surplus to non-spouse sharers) ---
  const total = merged.reduce((s, x) => s + x.fraction, 0);
  if (total > 1.0000001) {
    // ʿAwl: the fixed shares over-subscribe, so every share shrinks proportionally.
    merged.forEach((x) => (x.fraction /= total));
  } else if (total < 0.9999999) {
    const surplus = 1 - total;
    // A spouse never takes by radd.
    const raddable = merged.filter((x) => x.relation !== 'HUSBAND' && x.relation !== 'WIFE');
    const base = raddable.reduce((s, x) => s + x.fraction, 0);

    const spouseOnly = base === 0 && merged.length > 0;

    if (base > 0 && RADD_SCHOOLS.includes(madhhab)) {
      raddable.forEach((x) => (x.fraction += surplus * (x.fraction / base)));
    } else if (spouseOnly && RADD_SCHOOLS.includes(madhhab)) {
      // A SPOUSE IS THE ONLY SURVIVOR — the surplus returns to them.
      //
      // The general rule above is right: a spouse never shares in radd alongside blood
      // relatives, because radd is a return to kin. But when there is no one else at all,
      // that rule was sending the rest of the estate to bayt al-māl — so a widow with no
      // children, parents or siblings took her eighth or quarter and watched three quarters
      // of her husband's estate go to a public treasury.
      //
      // In the jurisdictions this product serves there IS no such treasury to receive it. A
      // will naming one names no legal person, so the share LAPSES: it falls into intestacy
      // and a secular court divides it among whichever relatives local law prefers — very
      // possibly the people the fara'id had already excluded. The classical rule presumes an
      // institution that would honour it; without that institution it produces the opposite
      // of its intent.
      //
      // So contemporary codification returns it to the spouse when nobody else survives —
      // Egyptian Law 77/1943 and the statutes that follow it. That is the same reasoning
      // already settled for Mālikī/Shāfiʿī radd in DECISIONS §21, applied to the case it
      // missed. Proportional, so multiple wives divide it as they divide their eighth.
      const spouseBase = merged.reduce((s, x) => s + x.fraction, 0);
      merged.forEach((x) => (x.fraction += surplus * (x.fraction / spouseBase)));
    } else {
      // Nobody survives at all, or a school that genuinely escheats. Shown as bayt al-māl's
      // rather than silently dropped, so the result always sums to 100%.
      merged.push({ relation: BAYT_AL_MAL, name: 'Bayt al-māl (public treasury)', fraction: surplus });
    }
  }

  // Apportion the final rounding so the displayed shares sum to exactly 100.00 —
  // the fractions above are the authority and are untouched.
  const percents = apportionPercents(merged.map((x) => x.fraction));
  return merged.map((x, i) => ({ heirRelation: x.relation, heirName: x.name, sharePercent: percents[i] }));
}

/** Enforces the hard Sharia cap: free bequests (the "1/3") can never exceed ~33.33% combined. */
export function validateBequests(bequests: { sharePercent: number }[]): void {
  const total = bequests.reduce((s, b) => s + b.sharePercent, 0);
  if (total > MAX_FREE_BEQUEST_PERCENT + 0.01) {
    throw new Error(
      `Bequests total ${total.toFixed(2)}%, which exceeds the Sharia-mandated maximum of 1/3 (${MAX_FREE_BEQUEST_PERCENT.toFixed(2)}%).`,
    );
  }
}
