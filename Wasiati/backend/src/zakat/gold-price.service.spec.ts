import { GoldPriceService, GOLD_SPOT_KEY, GOLD_MAX_AGE_HOURS } from './gold-price.service';

/**
 * The live gold feed behind the zakat estimate. The failure modes matter more than the
 * happy path, because the number states a religious obligation:
 *
 *   1. UNIT MISTAKES. The feed quotes per TROY OUNCE; nisāb is in grams. A shape change
 *      that slips per-ounce through as per-gram is ~31× wrong — the sanity band refuses
 *      anything outside $20–$1,000/g rather than storing it.
 *   2. LOSING GOOD DATA. A dead feed, a broken rate, or an implausible print must cost
 *      at most one currency one tick — never a still-fresh stored price. Carried-forward
 *      prices keep their ORIGINAL timestamp, so they still expire on schedule.
 *   3. CONFIDENT NONSENSE. An in-band-looking FX rate that is wildly wrong (CAD as
 *      14.072) would beat the correct env fallback for 72h. Floating currencies get a
 *      plausibility band; SAR never consults the feed at all — it is hard-pegged at
 *      3.75 (USD_PEG, geo.util: "needs no FX feed").
 */
const XAU = 4099.2; // USD per troy ounce; 4099.2 / 31.1034768 = 131.7923... USD/g
const G = 31.1034768;

function makeService(opts: {
  stored?: { perGram: Record<string, { minor: number; at: string }> } | { at: string; perGramMinor: any } | null;
  xau?: any;
  fx?: any;
  xauFails?: boolean;
  fxFails?: boolean;
}) {
  const settings = new Map<string, any>();
  if (opts.stored) settings.set(GOLD_SPOT_KEY, { key: GOLD_SPOT_KEY, value: JSON.stringify(opts.stored) });

  const prisma: any = {
    appSetting: {
      findUnique: async ({ where }: any) => settings.get(where.key) ?? null,
      upsert: async ({ where, create, update }: any) => {
        const existing = settings.get(where.key);
        const row = existing ? { ...existing, ...update } : create;
        settings.set(where.key, row);
        return row;
      },
    },
  };
  const config: any = { get: () => undefined };
  const svc = new GoldPriceService(prisma, config);

  // Fake the two HTTP calls at the private seam, keeping the parse/convert/store logic real.
  (svc as any).getJson = async (url: string) => {
    if (url.includes('gold-api')) {
      if (opts.xauFails) throw new Error('gold feed down');
      return opts.xau ?? { price: XAU, symbol: 'XAU' };
    }
    if (opts.fxFails) throw new Error('fx feed down');
    return opts.fx ?? { result: 'success', rates: { USD: 1, CAD: 1.4072, SAR: 3.75 } };
  };

  return { svc, stored: () => settings.get(GOLD_SPOT_KEY) };
}

const FRESH = new Date(Date.now() - 3_600_000).toISOString(); // 1h ago
const STALE = new Date(Date.now() - (GOLD_MAX_AGE_HOURS + 10) * 3_600_000).toISOString();

describe('GoldPriceService.refresh', () => {
  it('converts ozt→gram→currency with ONE terminal rounding per currency', async () => {
    const { svc } = makeService({});
    const spot = await svc.refresh();

    // Single rounding: round(ozt/G * rate * 100) — NOT round(round(ozt/G*100) * rate).
    // The difference is 1–2 minor units in ~half of inputs; on an 85g nisāb that is
    // up to SAR 1.70 sitting exactly on the owe/not-owe line.
    expect(spot!.perGram.USD.minor).toBe(Math.round((XAU / G) * 100)); // 13179
    expect(spot!.perGram.CAD.minor).toBe(Math.round((XAU / G) * 1.4072 * 100)); // 18546, not 18545
    expect(spot!.perGram.SAR.minor).toBe(Math.round((XAU / G) * 3.75 * 100)); // 49422, not 49421
  });

  it('prices SAR from the HARD PEG, never the feed — a feed cannot mis-price KSA', async () => {
    // The FX feed answers SAR 37.5 (10× wrong, plausibly in any generic band).
    const { svc } = makeService({ fx: { rates: { CAD: 1.4072, SAR: 37.5 } } });
    const spot = await svc.refresh();
    expect(spot!.perGram.SAR.minor).toBe(Math.round((XAU / G) * 3.75 * 100));
  });

  // THE unit tripwire: per-OUNCE slipping through as per-gram is ~31× too high, and a
  // feed that switched to per-kilo would be ~32× too low. Both land outside $20–$1,000/g.
  it('REFUSES an implausible gold price instead of storing it', async () => {
    const good = { perGram: { USD: { minor: 13_000, at: FRESH } } };
    for (const price of [XAU * 31.1, 4.09]) {
      const { svc, stored } = makeService({ stored: good, xau: { price } });
      expect(await svc.refresh()).toBeNull();
      expect(JSON.parse(stored().value)).toEqual(good); // previous value untouched
    }
    // Zero/negative/absent: not a price at all — treated exactly like a dead feed.
    for (const price of [0, -5, undefined]) {
      const { svc, stored } = makeService({ stored: good, xau: { price } });
      await expect(svc.refresh()).rejects.toThrow(/no usable price/);
      expect(JSON.parse(stored().value)).toEqual(good);
    }
  });

  it('REFUSES an out-of-band CAD rate — confidently wrong beats-the-env is the worst outcome', async () => {
    const good = { perGram: { CAD: { minor: 18_000, at: FRESH } } };
    // 14.072: a decimal-point slip that a "rate > 0" check happily accepts.
    const { svc, stored } = makeService({ stored: good, fx: { rates: { CAD: 14.072, SAR: 3.75 } } });
    const spot = await svc.refresh();
    // CAD carried forward under its ORIGINAL timestamp; USD and SAR updated fresh.
    expect(spot!.perGram.CAD).toEqual(good.perGram.CAD);
    expect(spot!.perGram.USD.minor).toBe(13_179);
    expect(spot!.perGram.SAR.minor).toBe(49_422);
    expect(JSON.parse(stored().value).perGram.CAD).toEqual(good.perGram.CAD);
  });

  it('a dead FX feed still updates USD and pegged SAR — they never needed it', async () => {
    const { svc } = makeService({ fxFails: true });
    const spot = await svc.refresh();
    expect(spot!.perGram.USD.minor).toBe(13_179);
    expect(spot!.perGram.SAR.minor).toBe(49_422);
    expect(spot!.perGram.CAD).toBeUndefined(); // nothing stored, nothing to carry
  });

  it('a broken single rate costs that currency ONE TICK, not its history', async () => {
    const good = { perGram: { CAD: { minor: 18_400, at: FRESH } } };
    const { svc } = makeService({ stored: good, fx: { rates: { CAD: 0, SAR: 3.75 } } });
    const spot = await svc.refresh();
    expect(spot!.perGram.CAD).toEqual(good.perGram.CAD); // carried, original timestamp
  });

  // The carry-forward must NOT re-stamp: a price carried under a fresh timestamp would
  // masquerade as current forever, defeating the 72h rule entirely.
  it('a carried price keeps its original `at` and still EXPIRES on schedule', async () => {
    const old = new Date(Date.now() - 70 * 3_600_000).toISOString(); // 70h — fresh, barely
    const { svc } = makeService({
      stored: { perGram: { CAD: { minor: 18_400, at: old } } },
      fxFails: true,
    });
    const spot = await svc.refresh();
    expect(spot!.perGram.CAD.at).toBe(old); // not re-stamped
    // 3 hours later it is 73h old and livePricePerGramMinor refuses it.
    const later = new Date(Date.now() + 3 * 3_600_000);
    expect(await svc.livePricePerGramMinor('CAD', later)).toBeNull();
  });

  it('a dead GOLD feed keeps the entire previous row', async () => {
    const good = { perGram: { USD: { minor: 13_000, at: FRESH } } };
    const { svc, stored } = makeService({ stored: good, xauFails: true });
    await expect(svc.refresh()).rejects.toThrow('gold feed down');
    expect(JSON.parse(stored().value)).toEqual(good);
  });
});

describe('GoldPriceService.livePricePerGramMinor — freshness per currency', () => {
  it('serves a fresh stored price', async () => {
    const { svc } = makeService({ stored: { perGram: { SAR: { minor: 49_422, at: FRESH } } } });
    expect(await svc.livePricePerGramMinor('SAR')).toBe(49_422);
  });

  it(`refuses one older than ${GOLD_MAX_AGE_HOURS}h — stale states a wrong obligation`, async () => {
    const { svc } = makeService({ stored: { perGram: { SAR: { minor: 49_422, at: STALE } } } });
    expect(await svc.livePricePerGramMinor('SAR')).toBeNull();
  });

  it('judges each currency by its OWN age — one stale entry does not poison the rest', async () => {
    const { svc } = makeService({
      stored: { perGram: { USD: { minor: 13_179, at: FRESH }, CAD: { minor: 18_400, at: STALE } } },
    });
    expect(await svc.livePricePerGramMinor('USD')).toBe(13_179);
    expect(await svc.livePricePerGramMinor('CAD')).toBeNull();
  });

  it('returns null for a currency the refreshes have never priced', async () => {
    const { svc } = makeService({ stored: { perGram: { USD: { minor: 13_179, at: FRESH } } } });
    expect(await svc.livePricePerGramMinor('CAD')).toBeNull();
  });

  it('treats the legacy single-timestamp shape as absent, not as data', async () => {
    // The old shape shared one `at` across currencies — the exact design the
    // per-currency shape replaced. Reading it as truth would resurrect the bug.
    const { svc } = makeService({
      stored: { at: FRESH, perGramMinor: { USD: 13_179 } } as any,
    });
    expect(await svc.livePricePerGramMinor('USD')).toBeNull();
  });

  it('survives nothing stored at all', async () => {
    const { svc } = makeService({});
    expect(await svc.livePricePerGramMinor('USD')).toBeNull();
  });
});
