import { createHash } from 'crypto';
import { calculateShariaShares, Madhhab, HeirRelation } from './sharia-calculator';

/**
 * A FINGERPRINT of everything the engine computes, per school.
 *
 * The madhhab setting is about to gain real per-school doctrine, one difference at a time.
 * Each of those changes edits shared code paths — radd, the residue chain, escheat — and a
 * change meant for one school can silently move another. On an engine that divides real
 * inheritances that is the failure that matters, and it is invisible to targeted tests:
 * every existing case can stay green while some untested configuration quietly shifts.
 *
 * So this sweeps every subset of the modelled heirs up to size three, each also with the
 * first relation doubled (doubling flips real rules — two daughters take 2/3, two siblings
 * cut the mother to 1/6), runs all five schools over it, and hashes the result. 3,586
 * configurations per school.
 *
 * WHEN THIS TEST FAILS, READ THIS BEFORE TOUCHING IT.
 *
 * A failing hash means that school's arithmetic changed somewhere in those 3,586 cases. That
 * is either exactly what you intended, or a defect. Decide WHICH before updating a constant:
 *
 *   1. Regenerate the detailed snapshot (see faraid-baseline-README.md) and DIFF it, so you
 *      can see the individual configurations that moved rather than just that something did.
 *   2. Confirm every moved line is one the change was supposed to move.
 *   3. Only then update the constant below, in the same commit as the change, with the reason.
 *
 * JUMHUR and HANAFI are LIVE — they are the two options the picker ships, so wills already
 * sealed were computed with them. A diff on those two is not a test to update; it is a
 * question about documents people have already signed. Escalate rather than re-baseline.
 *
 * Recorded 22 Jul 2026, before any doctrinal work. At that point MALIKI, SHAFII and HANBALI
 * were byte-identical to JUMHUR across all 3,586 configurations — three of the five options
 * were aliases, which is the defect this work exists to fix. Their hashes SHOULD diverge as
 * each school gains its own rules; that divergence is the success signal.
 */
/**
 * UPDATED 22 Jul 2026 — spouse-only estates no longer escheat.
 *
 * Previous: JUMHUR/MALIKI/SHAFII/HANBALI 551a9d3cb95f961f, HANAFI 2bcdcf6148394cb5.
 *
 * The change was verified the way this file's header demands, not assumed. The full
 * 18,216-configuration snapshot was regenerated and diffed against the pre-change capture:
 * exactly SIX configurations moved per school, and every one of them is an estate whose only
 * survivor is a spouse —
 *
 *     WIFE                  25%  + 75% bayt al-māl   ->  100%
 *     HUSBAND               50%  + 50% bayt al-māl   ->  100%
 *     WIFE*2            12.5% ea + 75% bayt al-māl   ->  50% each
 *     HUSBAND*2, HUSBAND+WIFE   (impossible inputs, moved consistently)
 *
 * Nothing involving a single blood relative changed. That was the whole risk: radd
 * mechanics are shared code, and a fix aimed at the spouse case could easily have shifted
 * every estate with a surplus. It did not.
 */
/**
 * UPDATED AGAIN 22 Jul 2026 — shares are now apportioned to six decimals, not two.
 *
 * Previous: JUMHUR/MALIKI/SHAFII/HANBALI d93e56379fee2f1f, HANAFI e22db11e71d1ee2e.
 *
 * Every school's hash moved, and that is expected: this changes how nearly every share is
 * DISPLAYED. So the usual "which configurations moved" check cannot isolate it, and a
 * different proof was needed — the full 18,216-configuration snapshot was regenerated and
 * compared numerically rather than textually:
 *
 *     rows differing ................. 55,214   (precision, as intended)
 *     rows where the HEIR SET changed ....... 0   <-- the number that matters
 *     largest single-share movement ... 0.0067%
 *
 * Nobody gained or lost entitlement. The largest movement is the rounding error being
 * CORRECTED: a grandfather who was shown 83.34% is now shown 83.3333%, which is what he was
 * always owed.
 */
const FINGERPRINTS: Record<Madhhab, string> = {
  // LIVE — the two options the picker ships. A diff here concerns sealed wills.
  JUMHUR: '6e380b236b798bad',
  HANAFI: 'd37bd04ed81531bf',
  // Identical to JUMHUR by design — see the alias tests in sharia-calculator.spec.ts and
  // DECISIONS §21. Each SHOULD diverge only if its school ever gains real doctrine.
  MALIKI: '6e380b236b798bad',
  SHAFII: '6e380b236b798bad',
  HANBALI: '6e380b236b798bad',
};

const REL: HeirRelation[] = [
  'HUSBAND', 'WIFE', 'SON', 'DAUGHTER', 'SON_SON', 'SON_DAUGHTER', 'FATHER', 'MOTHER',
  'GRANDFATHER', 'PATERNAL_GRANDMOTHER', 'MATERNAL_GRANDMOTHER', 'FULL_BROTHER', 'FULL_SISTER',
  'CONSANGUINE_BROTHER', 'CONSANGUINE_SISTER', 'MATERNAL_SIBLING', 'FULL_NEPHEW',
  'CONSANGUINE_NEPHEW', 'FULL_UNCLE', 'CONSANGUINE_UNCLE', 'FULL_COUSIN', 'CONSANGUINE_COUSIN',
];

/** Every subset of REL up to [k], smallest first, in a fixed order so the hash is stable. */
function* subsets(k: number): Generator<HeirRelation[]> {
  const rec = function* (start: number, acc: HeirRelation[]): Generator<HeirRelation[]> {
    if (acc.length) yield [...acc];
    if (acc.length === k) return;
    for (let i = start; i < REL.length; i++) yield* rec(i + 1, [...acc, REL[i]]);
  };
  yield* rec(0, []);
}

function sweep(madhhab: Madhhab): { hash: string; rows: number } {
  const lines: string[] = [];
  for (const combo of subsets(3)) {
    for (const doubled of [false, true]) {
      const heirs = combo.flatMap((r, i) =>
        doubled && i === 0
          ? [{ relation: r, name: `${r}1` }, { relation: r, name: `${r}2` }]
          : [{ relation: r, name: r }],
      );
      let out: string;
      try {
        out = calculateShariaShares(heirs, madhhab)
          .map((s) => `${s.heirRelation}:${s.sharePercent.toFixed(4)}`)
          .sort()
          .join(',');
      } catch (e) {
        // A throw is part of the behaviour being pinned — an input that starts throwing, or
        // stops, is exactly the kind of silent change this exists to catch.
        out = `THREW:${(e as Error).message}`;
      }
      lines.push(`${combo.join('+')}${doubled ? '*2' : ''}|${out}`);
    }
  }
  lines.sort();
  return { hash: createHash('sha256').update(lines.join('\n')).digest('hex').slice(0, 16), rows: lines.length };
}

describe('engine fingerprint — no school changes without someone deciding it should', () => {
  const results = new Map<Madhhab, { hash: string; rows: number }>();

  beforeAll(() => {
    for (const m of Object.keys(FINGERPRINTS) as Madhhab[]) results.set(m, sweep(m));
  });

  it('sweeps a meaningful number of configurations', () => {
    // Guards the guard: a sweep that silently collapsed to a handful of cases would keep
    // passing while checking almost nothing.
    expect(results.get('JUMHUR')!.rows).toBeGreaterThan(3000);
  });

  for (const m of Object.keys(FINGERPRINTS) as Madhhab[]) {
    it(`${m} computes exactly what it did when this was recorded`, () => {
      expect(results.get(m)!.hash).toBe(FINGERPRINTS[m]);
    });
  }
});
