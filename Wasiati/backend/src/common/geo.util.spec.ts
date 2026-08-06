import { Region } from '@prisma/client';
import {
  assertResidency,
  convertPeggedMinor,
  convertToFallbackMinor,
  countryToRegion,
  deploymentRegion,
  isFallbackCurrency,
  isPegged,
  REGION_CURRENCY,
  resolveBillingCurrency,
  ResidencyViolationError,
  servedRegions,
} from './geo.util';

describe('geo.util', () => {
  const ORIGINAL = { ...process.env };
  afterEach(() => {
    process.env = { ...ORIGINAL };
  });

  describe('billing currency', () => {
    it('bills every region in its own currency by default', () => {
      delete process.env.PAYMENT_ENABLED_CURRENCIES;
      expect(resolveBillingCurrency(Region.US)).toBe('USD');
      expect(resolveBillingCurrency(Region.CA)).toBe('CAD');
      expect(resolveBillingCurrency(Region.KSA)).toBe('SAR');
    });

    it('falls back to USD when the region currency is not enabled on the account', () => {
      process.env.PAYMENT_ENABLED_CURRENCIES = 'USD,CAD'; // SAR deliberately absent
      expect(resolveBillingCurrency(Region.KSA)).toBe('USD');
      expect(isFallbackCurrency(Region.KSA)).toBe(true);
      // ...and leaves the others alone
      expect(resolveBillingCurrency(Region.CA)).toBe('CAD');
      expect(isFallbackCurrency(Region.CA)).toBe(false);
    });

    it('every region has a currency defined', () => {
      for (const r of Object.values(Region)) expect(REGION_CURRENCY[r]).toBeTruthy();
    });
  });

  describe('fallback conversion', () => {
    it('CONVERTS rather than relabels — 746 SAR is ~$199, not $746', () => {
      // Relabelling a 74600 SAR-minor price as USD would charge $746.00 instead of $199.
      expect(convertToFallbackMinor(74600, 'SAR')).toBe(19893); // 746 / 3.75 ≈ 198.93
    });

    it('converts SAR at its peg', () => {
      expect(convertToFallbackMinor(74500, 'SAR')).toBe(19867); // 745 / 3.75 ≈ 198.67
    });

    it('is a no-op for USD', () => {
      expect(convertToFallbackMinor(19900, 'USD')).toBe(19900);
    });

    it('REFUSES to guess an FX rate for a floating currency', () => {
      // CAD has no fixed peg. Charging a customer at a guessed rate is unacceptable.
      expect(() => convertToFallbackMinor(1999, 'CAD')).toThrow(/no fixed peg/i);
    });
  });

  describe('convertPeggedMinor (estimate-only cross-peg conversion)', () => {
    it('is a no-op for the same currency', () => {
      expect(convertPeggedMinor(5000, 'SAR', 'SAR')).toBe(5000);
    });

    it('converts between two pegged currencies via their USD pegs', () => {
      // 3640 QAR = $1000 = 3750 SAR.
      expect(convertPeggedMinor(3640, 'QAR', 'SAR')).toBe(3750);
      // …and back.
      expect(convertPeggedMinor(3750, 'SAR', 'QAR')).toBe(3640);
    });

    it('returns NULL (never a guess) when either side floats', () => {
      expect(convertPeggedMinor(5000, 'CAD', 'SAR')).toBeNull();
      expect(convertPeggedMinor(5000, 'SAR', 'CAD')).toBeNull();
      expect(convertPeggedMinor(5000, 'EUR', 'GBP')).toBeNull();
    });

    it('is case-insensitive on the currency codes', () => {
      expect(convertPeggedMinor(3640, 'qar', 'sar')).toBe(3750);
    });
  });

  describe('isPegged', () => {
    it('is true only for the fixed-peg currencies', () => {
      expect(isPegged('USD')).toBe(true);
      expect(isPegged('SAR')).toBe(true);
      expect(isPegged('QAR')).toBe(true);
      expect(isPegged('CAD')).toBe(false);
      expect(isPegged('EUR')).toBe(false);
    });
  });

  describe('country mapping', () => {
    it('maps Saudi correctly, and defaults the rest to US', () => {
      expect(countryToRegion('SA')).toBe(Region.KSA); // Saudi's ISO code is SA, not KSA
      // Qatar is no longer a market, so it falls to the US default like anywhere unlisted.
      expect(countryToRegion('QA')).toBe(Region.US);
      expect(countryToRegion('GB')).toBe(Region.US);
      expect(countryToRegion(null)).toBe(Region.US);
    });
  });

  describe('data residency', () => {
    it('refuses to start without a valid REGION rather than defaulting', () => {
      delete process.env.REGION;
      expect(() => deploymentRegion()).toThrow(/REGION must be one of/);
      process.env.REGION = 'ATLANTIS';
      expect(() => deploymentRegion()).toThrow(/REGION must be one of/);
    });

    it('accepts a user whose region matches this deployment', () => {
      process.env.REGION = 'CA';
      expect(() => assertResidency(Region.CA)).not.toThrow();
    });

    it('BLOCKS writing a KSA user into the US database', () => {
      process.env.REGION = 'US';
      expect(() => assertResidency(Region.KSA)).toThrow(ResidencyViolationError);
    });

    it('blocks a Canadian user on the Saudi deployment', () => {
      process.env.REGION = 'KSA';
      expect(() => assertResidency(Region.CA)).toThrow(/must be created on the CA service/);
    });
  });

  describe('served regions (single-stack launch topology)', () => {
    it('defaults to serving only the deployment region', () => {
      process.env.REGION = 'CA';
      delete process.env.SERVED_REGIONS;
      expect(servedRegions()).toEqual([Region.CA]);
    });

    it('one stack can serve every market — the launch topology', () => {
      process.env.REGION = 'CA';
      process.env.SERVED_REGIONS = 'US,CA,KSA';
      expect(() => assertResidency(Region.KSA)).not.toThrow();
      expect(() => assertResidency(Region.US)).not.toThrow();
      expect(() => assertResidency(Region.CA)).not.toThrow();
    });

    it('removing a market refuses its NEW signups — how a dedicated stack splits off', () => {
      process.env.REGION = 'CA';
      process.env.SERVED_REGIONS = 'US,CA'; // KSA has its own stack now
      expect(() => assertResidency(Region.KSA)).toThrow(ResidencyViolationError);
    });

    it('tolerates spacing and case, and dedupes', () => {
      process.env.REGION = 'US';
      process.env.SERVED_REGIONS = ' us , ca , us ';
      expect(servedRegions()).toEqual([Region.US, Region.CA]);
    });

    it('refuses to run with an unknown region rather than silently narrowing signups', () => {
      process.env.REGION = 'US';
      process.env.SERVED_REGIONS = 'US,QA'; // Qatar is not a region any more
      expect(() => servedRegions()).toThrow(/unknown region/i);
    });
  });
});
