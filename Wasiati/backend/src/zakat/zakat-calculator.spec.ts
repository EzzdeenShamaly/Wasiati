import { AssetType } from '@prisma/client';
import { estimateZakat, isValidHawl, nisabMinor, NISAB_GOLD_GRAMS, ZAKAT_RATE_BP } from './zakat-calculator';

/**
 * Spec §5 and acceptance criterion 11:
 *   "Zakat: crypto never enters the base; below-nisab -> 'no zakat due';
 *    'Pay your zakah' renders only while an admin charity link is published;
 *    hawl input accepts Hijri only."
 *
 * Base is cash + shares + gold (+ bank balances). Rate is rubʿ al-ʿushr, 2.5%.
 * Niṣāb is the value of 85 g of gold — the spec's worked figure is SAR 42,500,
 * i.e. SAR 500 per gram.
 */
const SAR_PER_GRAM = 50_000; // SAR 500.00 in minor units

const asset = (type: AssetType, majorUnits: number, currency = 'SAR') => ({
  type,
  amountMinor: majorUnits * 100,
  currency,
});

const run = (assets: ReturnType<typeof asset>[], currency = 'SAR', gold = SAR_PER_GRAM) =>
  estimateZakat({ assets, currency, goldPricePerGramMinor: gold });

describe('zakat estimator', () => {
  describe('niṣāb', () => {
    it('is 85 g of gold — SAR 42,500 at SAR 500/g (spec §5)', () => {
      expect(NISAB_GOLD_GRAMS).toBe(85);
      expect(nisabMinor(SAR_PER_GRAM)).toBe(4_250_000); // SAR 42,500.00
    });

    it('below niṣāb, no zakat is due', () => {
      const r = run([asset(AssetType.CASH, 42_499)]);
      expect(r.aboveNisab).toBe(false);
      expect(r.zakatDueMinor).toBe(0);
    });

    it('exactly at niṣāb, zakat IS due', () => {
      const r = run([asset(AssetType.CASH, 42_500)]);
      expect(r.aboveNisab).toBe(true);
      expect(r.zakatDueMinor).toBe(106_250); // 42,500 * 2.5% = SAR 1,062.50
    });
  });

  describe('the base', () => {
    it('CRYPTO never enters the base — and is disclosed, not hidden', () => {
      const r = run([
        asset(AssetType.CASH, 50_000),
        asset(AssetType.CRYPTO, 1_000_000), // would dwarf everything if counted
      ]);

      expect(r.zakatableTotalMinor).toBe(5_000_000); // cash only
      expect(r.categories.map((c) => c.type)).toEqual([AssetType.CASH]);
      expect(r.excluded).toEqual([
        { type: AssetType.CRYPTO, totalMinor: 100_000_000, currency: 'SAR', reasonKey: 'zakat.excluded.crypto' },
      ]);
    });

    it('counts cash, bank, shares and gold', () => {
      const r = run([
        asset(AssetType.CASH, 10_000),
        asset(AssetType.BANK_ACCOUNT, 20_000),
        asset(AssetType.SHARES, 15_000),
        asset(AssetType.GOLD, 5_000),
      ]);
      expect(r.zakatableTotalMinor).toBe(5_000_000); // SAR 50,000
      expect(r.categories).toHaveLength(4);
      expect(r.categories.every((c) => c.basisKey.startsWith('zakat.basis.'))).toBe(true);
    });

    it('leaves real estate, vehicles, pensions and businesses out of the base', () => {
      const r = run([
        asset(AssetType.CASH, 50_000),
        asset(AssetType.REAL_ESTATE, 2_000_000),
        asset(AssetType.VEHICLE, 100_000),
        asset(AssetType.PENSION, 500_000),
        asset(AssetType.BUSINESS_OWNERSHIP, 800_000),
      ]);
      expect(r.zakatableTotalMinor).toBe(5_000_000);
    });

    it('ignores liabilities rather than deducting them (see docs/FIQH_REVIEW.md)', () => {
      const withDebt = run([asset(AssetType.CASH, 50_000), asset(AssetType.LIABILITY, 40_000)]);
      const without = run([asset(AssetType.CASH, 50_000)]);
      expect(withDebt.zakatableTotalMinor).toBe(without.zakatableTotalMinor);
    });

    it('skips zero and negative values', () => {
      const r = run([asset(AssetType.CASH, 50_000), asset(AssetType.GOLD, 0), asset(AssetType.SHARES, -100)]);
      expect(r.zakatableTotalMinor).toBe(5_000_000);
    });
  });

  describe('the rate', () => {
    it('is rubʿ al-ʿushr — 2.5%', () => {
      expect(ZAKAT_RATE_BP).toBe(250);
      const r = run([asset(AssetType.CASH, 100_000)]);
      expect(r.zakatDueMinor).toBe(250_000); // SAR 2,500
    });

    it('rounds DOWN, never overstating what is owed', () => {
      // 42,500.01 -> 2.5% = 1062.50025 -> floor to the minor unit.
      const r = estimateZakat({
        assets: [{ type: AssetType.CASH, amountMinor: 4_250_001, currency: 'SAR' }],
        currency: 'SAR',
        goldPricePerGramMinor: SAR_PER_GRAM,
      });
      expect(r.zakatDueMinor).toBe(106_250);
    });
  });

  describe('mixed currencies', () => {
    it('converts pegged currencies exactly (QAR -> SAR via their USD pegs)', () => {
      // 3,640 QAR = $1,000 = 3,750 SAR
      const r = run([asset(AssetType.CASH, 3_640, 'QAR')]);
      expect(r.zakatableTotalMinor).toBe(375_000);
      expect(r.unconverted).toEqual([]);
    });

    it('REFUSES to convert a floating currency, and discloses it', () => {
      // CAD has no fixed peg. Guessing a rate would mis-state somebody's zakat.
      const r = run([asset(AssetType.CASH, 50_000), asset(AssetType.SHARES, 10_000, 'CAD')]);

      expect(r.zakatableTotalMinor).toBe(5_000_000); // the CAD shares are NOT counted
      expect(r.unconverted).toEqual([{ currency: 'CAD', totalMinor: 1_000_000, count: 1 }]);
    });

    it('groups several unconvertible assets by currency', () => {
      const r = run([
        asset(AssetType.CASH, 1_000, 'CAD'),
        asset(AssetType.GOLD, 500, 'CAD'),
        asset(AssetType.SHARES, 200, 'EUR'),
      ]);
      expect(r.unconverted).toEqual(
        expect.arrayContaining([
          { currency: 'CAD', totalMinor: 150_000, count: 2 },
          { currency: 'EUR', totalMinor: 20_000, count: 1 },
        ]),
      );
      expect(r.zakatableTotalMinor).toBe(0);
    });
  });

  describe('ḥawl — Hijri only', () => {
    it('accepts a Hijri day and month', () => {
      expect(isValidHawl(1, 1)).toBe(true);
      expect(isValidHawl(30, 12)).toBe(true);
    });

    it('rejects a 31st day (no Hijri month has one) and a 13th month', () => {
      expect(isValidHawl(31, 1)).toBe(false);
      expect(isValidHawl(15, 13)).toBe(false);
      expect(isValidHawl(0, 5)).toBe(false);
      expect(isValidHawl(1.5, 5)).toBe(false);
    });
  });
});
