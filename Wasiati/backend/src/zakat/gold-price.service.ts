import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { CRON_LOCKS, withCronLock } from '../common/cron-lock';
import { REGION_CURRENCY, USD_PEG } from '../common/geo.util';

/**
 * AppSetting row holding the last good prices, PER CURRENCY:
 * `{ perGram: { USD: { minor, at }, CAD: { minor, at }, ... } }`.
 *
 * Per-currency timestamps are load-bearing, not decoration. One shared timestamp
 * forces a choice between two bad behaviours when a single FX rate is broken: drop
 * the currency (destroying a still-fresh price and 503ing that region's users), or
 * carry the old value under the new shared timestamp (re-stamping it fresh forever,
 * defeating the staleness rule). Each currency carrying its own `at` dissolves the
 * dilemma — a carried-forward price keeps its ORIGINAL time and expires on its own
 * schedule, exactly as if the broken tick had never happened.
 */
export const GOLD_SPOT_KEY = 'zakat.goldSpot';

/** Troy ounce → grams. The feed quotes XAU per ozt; nisāb is measured in grams. */
const GRAMS_PER_TROY_OUNCE = 31.1034768;

/**
 * How old a stored price may be before the estimate refuses to use it. Gold trades
 * ~23h × 5 days, so a weekend plus a market holiday can legitimately leave the latest
 * print ~3 days old; beyond that something is broken and the stale-price rule applies
 * ("a stale gold price mis-states somebody's religious obligation" — zakat.service.ts).
 */
export const GOLD_MAX_AGE_HOURS = 72;

/**
 * Unit-mistake tripwires, not market forecasts. Gold has never traded near $20/g or
 * $1,000/g; a value outside this band means the feed changed shape (per-ounce read as
 * per-gram would be ~$4,100/g, per-kilo ~$131,000/g) and must be REFUSED, because the
 * one thing worse than no price is a confidently wrong one.
 */
const USD_PER_GRAM_MIN = 20;
const USD_PER_GRAM_MAX = 1_000;

/**
 * Plausibility band per FLOATING currency the FX feed is allowed to price. An
 * in-band-looking rate that is nonetheless wildly wrong (CAD delivered as 14.072)
 * would otherwise store a confidently wrong price that BEATS the correct env
 * fallback for 72 hours — worse than no rate at all. CAD has spent five decades
 * inside 0.95–1.62 per USD; a print outside this band is a feed defect.
 *
 * SAR deliberately has no row here: it is HARD-PEGGED at 3.75 (USD_PEG, geo.util),
 * whose own comment says "needs no FX feed". The peg is used directly, so no feed
 * opinion can ever mis-price the KSA region.
 */
const FX_BANDS: Record<string, [number, number]> = {
  CAD: [0.9, 2.0],
};

const FETCH_TIMEOUT_MS = 10_000;

export interface GoldSpot {
  perGram: Record<string, { minor: number; at: string }>;
}

/**
 * Live gold spot for the zakat estimate — the user asked for this from the start:
 * nisāb priced in the user's own currency, current, with no manual babysitting.
 *
 * Two keyless public feeds (no secret to provision, nothing in .env to leak):
 *   - XAU/USD spot per troy ounce (gold-api.com)
 *   - USD→CAD reference rate (open.er-api.com) — pegged currencies never consult it
 * Overridable via ZAKAT_GOLD_FEED_URL / ZAKAT_FX_FEED_URL if either ever dies.
 *
 * A currency's stored price is replaced ONLY by a value that passed every check for
 * THAT currency; anything else carries the previous value forward under its original
 * timestamp. A dead FX feed therefore cannot stale USD or the pegged currencies, and
 * a broken single rate costs one currency one tick, not its history. ZakatService
 * reads fresh-first, falls back to the ZAKAT_GOLD_PRICE_PER_GRAM_* env values (the
 * manual override for a dead feed), and 503s when both are gone.
 */
@Injectable()
export class GoldPriceService implements OnModuleInit {
  private readonly logger = new Logger(GoldPriceService.name);

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
  ) {}

  /**
   * Boot: make a price exist without waiting for the first cron tick. DELIBERATELY
   * not awaited — Nest blocks app start on onModuleInit promises, and two hung feeds
   * would hold every route (health checks included) hostage for the fetch timeout.
   * The estimate degrades to the env fallback until the warm-up lands.
   */
  onModuleInit() {
    void this.warmUp();
  }

  private async warmUp() {
    try {
      const spot = await this.currentSpot();
      if (!spot || Object.keys(spot.perGram).length === 0) await this.refresh();
    } catch (e) {
      this.logger.error(`Gold price warm-up failed (estimate falls back to env): ${(e as Error).message}`);
    }
  }

  /** Every 6 hours: cheap (2 requests), and keeps the 72h freshness window comfortable. */
  @Cron(CronExpression.EVERY_6_HOURS)
  async refreshCron() {
    await withCronLock(this.prisma, CRON_LOCKS.goldPriceRefresh, 'gold-price-refresh', () => this.refresh());
  }

  /** The stored spot, unfiltered — freshness is judged per currency by the caller. */
  async currentSpot(): Promise<GoldSpot | null> {
    const row = await this.prisma.appSetting.findUnique({ where: { key: GOLD_SPOT_KEY } });
    if (!row) return null;
    try {
      const parsed = JSON.parse(row.value);
      if (parsed && typeof parsed.perGram === 'object' && parsed.perGram) return parsed as GoldSpot;
      return null; // unknown/legacy shape — the next refresh overwrites it
    } catch {
      return null;
    }
  }

  /** Fresh per-gram price in minor units of `currency`, or null when unavailable/stale. */
  async livePricePerGramMinor(currency: string, now: Date = new Date()): Promise<number | null> {
    const spot = await this.currentSpot();
    const entry = spot?.perGram?.[currency.toUpperCase()];
    if (!entry) return null;
    const at = Date.parse(entry.at ?? '');
    if (!Number.isFinite(at) || now.getTime() - at > GOLD_MAX_AGE_HOURS * 3_600_000) return null;
    return typeof entry.minor === 'number' && Number.isFinite(entry.minor) && entry.minor > 0
      ? Math.round(entry.minor)
      : null;
  }

  /**
   * Fetch spot (+ FX for floating currencies), convert, and store per currency.
   * Rounding happens ONCE, at the end of each currency's own chain — rounding USD
   * to integer minor units first and multiplying the rounded value by FX compounds
   * two roundings and lands 1–2 minor units off in ~half of all inputs, which on an
   * 85-gram nisāb is up to SAR 1.70 sitting exactly on the owe/not-owe line.
   */
  async refresh(): Promise<GoldSpot | null> {
    const usdPerOzt = await this.fetchXauUsd();
    const usdPerGram = usdPerOzt / GRAMS_PER_TROY_OUNCE;
    if (usdPerGram < USD_PER_GRAM_MIN || usdPerGram > USD_PER_GRAM_MAX) {
      this.logger.error(
        `Gold feed returned an implausible price ($${usdPerGram.toFixed(2)}/g from ${usdPerOzt}/ozt) — ` +
          'refusing to store it. The estimate keeps the previous price.',
      );
      return null;
    }

    // The FX feed is only needed for floating currencies. Its failure must not stop
    // USD and the pegged currencies updating — that was the bug: one dead feed staled
    // ALL prices, including the ones that never needed it.
    let fx: Record<string, number> = {};
    const needsFx = Object.values(REGION_CURRENCY).some((c) => USD_PEG[c] === undefined);
    if (needsFx) {
      try {
        fx = await this.fetchUsdRates();
      } catch (e) {
        this.logger.error(`FX feed failed (${(e as Error).message}); floating currencies carry forward.`);
      }
    }

    // Start from what is already stored: a currency this tick cannot price keeps its
    // previous value AND its previous timestamp, so it still expires on schedule.
    const previous = (await this.currentSpot())?.perGram ?? {};
    const perGram: GoldSpot['perGram'] = { ...previous };
    const at = new Date().toISOString();

    for (const currency of Object.values(REGION_CURRENCY)) {
      const rate = USD_PEG[currency] ?? fx[currency];
      const band = FX_BANDS[currency];
      if (USD_PEG[currency] === undefined) {
        if (!Number.isFinite(rate) || rate <= 0) {
          this.logger.error(`No usable USD→${currency} rate; ${currency} carries forward.`);
          continue;
        }
        if (band && (rate < band[0] || rate > band[1])) {
          this.logger.error(
            `USD→${currency} rate ${rate} is outside the plausible band [${band[0]}, ${band[1]}] — ` +
              `a confidently wrong price is worse than none. ${currency} carries forward.`,
          );
          continue;
        }
      }
      perGram[currency] = { minor: Math.round(usdPerGram * rate * 100), at };
    }

    const spot: GoldSpot = { perGram };
    await this.prisma.appSetting.upsert({
      where: { key: GOLD_SPOT_KEY },
      create: { key: GOLD_SPOT_KEY, value: JSON.stringify(spot), updatedBy: 'gold-price-cron' },
      update: { value: JSON.stringify(spot), updatedBy: 'gold-price-cron' },
    });
    this.logger.log(
      `Gold spot refreshed: ${Object.entries(perGram)
        .map(([c, e]) => `${c} ${(e.minor / 100).toFixed(2)}/g${e.at === at ? '' : ' (carried)'}`)
        .join(', ')}`,
    );
    return spot;
  }

  private feedUrl(): string {
    return this.config.get<string>('ZAKAT_GOLD_FEED_URL') || 'https://api.gold-api.com/price/XAU';
  }

  private fxUrl(): string {
    return this.config.get<string>('ZAKAT_FX_FEED_URL') || 'https://open.er-api.com/v6/latest/USD';
  }

  /** XAU spot in USD per troy ounce. Throws on any shape it does not recognise. */
  private async fetchXauUsd(): Promise<number> {
    const data = await this.getJson(this.feedUrl());
    const price = Number(data?.price);
    if (!Number.isFinite(price) || price <= 0) {
      throw new Error(`Gold feed returned no usable price (got: ${JSON.stringify(data?.price)})`);
    }
    return price;
  }

  /** USD→X reference rates, e.g. { CAD: 1.4072, ... }. */
  private async fetchUsdRates(): Promise<Record<string, number>> {
    const data = await this.getJson(this.fxUrl());
    const rates = data?.rates;
    if (!rates || typeof rates !== 'object') {
      throw new Error('FX feed returned no rates object');
    }
    return rates as Record<string, number>;
  }

  private async getJson(url: string): Promise<any> {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(url, { signal: abort.signal });
      if (!res.ok) throw new Error(`${url} answered ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }
}
