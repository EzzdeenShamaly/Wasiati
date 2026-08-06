import { AssetType } from '@prisma/client';
import { convertPeggedMinor } from '../common/geo.util';

/**
 * Zakat al-māl estimator.
 *
 * GUIDANCE, NOT A RULING. Every figure here is an estimate; the user is told to
 * verify with a scholar (spec §5 requires a prominent warning).
 *
 * Rate: rubʿ al-ʿushr — a quarter of a tenth, 2.5%.
 * Niṣāb: the value of 85 g of gold. Below it, no zakat is due.
 *
 * Base (spec §5): **cash, shares and gold only.** Crypto is deliberately EXCLUDED —
 * its zakatability is contested and the product takes no position. Real estate,
 * vehicles, pensions and business ownership are outside the base too: they are
 * either non-zakatable in the common case or need a rule this estimator does not
 * model (trade goods, growth assets).
 *
 * Debts are NOT deducted. The spec defines the base additively, and deducting
 * liabilities is a fiqh judgement we have not had reviewed — see docs/FIQH_REVIEW.md.
 */

/** 2.5%, in basis points. */
export const ZAKAT_RATE_BP = 250;

/** Niṣāb is the value of this much gold. */
export const NISAB_GOLD_GRAMS = 85;

/** The only asset types that enter the zakat base. */
export const ZAKATABLE_TYPES: readonly AssetType[] = [
  AssetType.CASH,
  AssetType.BANK_ACCOUNT,
  AssetType.SHARES,
  AssetType.GOLD,
];

/** Held, and deliberately not counted. Surfaced to the user, not hidden. */
export const EXCLUDED_TYPES: readonly AssetType[] = [AssetType.CRYPTO];

export interface ZakatAsset {
  type: AssetType;
  amountMinor: number;
  currency: string;
}

export interface ZakatCategory {
  type: AssetType;
  totalMinor: number;
  /** Localisation key for the fiqh basis line shown under the category. */
  basisKey: string;
}

export interface ZakatEstimate {
  currency: string;
  categories: ZakatCategory[];
  /** Assets we hold but deliberately leave out, with the reason. */
  excluded: { type: AssetType; totalMinor: number; currency: string; reasonKey: string }[];
  /**
   * Assets we could NOT convert into `currency` because one side floats. They are
   * excluded from the base and disclosed — never converted at a guessed rate.
   */
  unconverted: { currency: string; totalMinor: number; count: number }[];
  zakatableTotalMinor: number;
  nisabMinor: number;
  aboveNisab: boolean;
  zakatDueMinor: number;
  rateBp: number;
}

const BASIS_KEYS: Partial<Record<AssetType, string>> = {
  [AssetType.CASH]: 'zakat.basis.cash',
  [AssetType.BANK_ACCOUNT]: 'zakat.basis.bank',
  [AssetType.SHARES]: 'zakat.basis.shares',
  [AssetType.GOLD]: 'zakat.basis.gold',
};

/** Niṣāb = 85 g × the price of one gram, in minor units of the same currency. */
export function nisabMinor(goldPricePerGramMinor: number): number {
  return Math.round(NISAB_GOLD_GRAMS * goldPricePerGramMinor);
}

/**
 * Computes the estimate in `currency`. `goldPricePerGramMinor` must be quoted in that
 * same currency — the caller is responsible for supplying a current price, because a
 * stale niṣāb is worse than no niṣāb.
 */
export function estimateZakat(params: {
  assets: ZakatAsset[];
  currency: string;
  goldPricePerGramMinor: number;
}): ZakatEstimate {
  const currency = params.currency.toUpperCase();

  const byCategory = new Map<AssetType, number>();
  const excludedByType = new Map<AssetType, number>();
  const unconvertedByCurrency = new Map<string, { totalMinor: number; count: number }>();

  for (const asset of params.assets) {
    if (asset.amountMinor <= 0) continue;

    // Crypto never enters the base, in any currency. Recorded so the UI can say so.
    if (EXCLUDED_TYPES.includes(asset.type)) {
      excludedByType.set(asset.type, (excludedByType.get(asset.type) ?? 0) + asset.amountMinor);
      continue;
    }
    if (!ZAKATABLE_TYPES.includes(asset.type)) continue;

    const converted = convertPeggedMinor(asset.amountMinor, asset.currency, currency);
    if (converted === null) {
      // A floating pair. Disclose it; never invent a rate for somebody's zakat.
      const row = unconvertedByCurrency.get(asset.currency.toUpperCase()) ?? { totalMinor: 0, count: 0 };
      row.totalMinor += asset.amountMinor;
      row.count += 1;
      unconvertedByCurrency.set(asset.currency.toUpperCase(), row);
      continue;
    }

    byCategory.set(asset.type, (byCategory.get(asset.type) ?? 0) + converted);
  }

  const categories: ZakatCategory[] = ZAKATABLE_TYPES.filter((t) => byCategory.has(t)).map((type) => ({
    type,
    totalMinor: byCategory.get(type)!,
    basisKey: BASIS_KEYS[type] ?? 'zakat.basis.other',
  }));

  const zakatableTotalMinor = categories.reduce((s, c) => s + c.totalMinor, 0);
  const nisab = nisabMinor(params.goldPricePerGramMinor);
  const aboveNisab = zakatableTotalMinor >= nisab;

  // Below niṣāb: no zakat is due. Round DOWN so we never overstate an obligation.
  const zakatDueMinor = aboveNisab ? Math.floor((zakatableTotalMinor * ZAKAT_RATE_BP) / 10_000) : 0;

  return {
    currency,
    categories,
    excluded: [...excludedByType.entries()].map(([type, totalMinor]) => ({
      type,
      totalMinor,
      currency, // amounts are as recorded; crypto is never converted
      reasonKey: 'zakat.excluded.crypto',
    })),
    unconverted: [...unconvertedByCurrency.entries()].map(([cur, r]) => ({
      currency: cur,
      totalMinor: r.totalMinor,
      count: r.count,
    })),
    zakatableTotalMinor,
    nisabMinor: nisab,
    aboveNisab,
    zakatDueMinor,
    rateBp: ZAKAT_RATE_BP,
  };
}

/** Ḥawl anniversary: Hijri day 1..30, Hijri month 1..12. Gregorian dates are rejected. */
export function isValidHawl(day: number, month: number): boolean {
  return Number.isInteger(day) && Number.isInteger(month) && day >= 1 && day <= 30 && month >= 1 && month <= 12;
}
