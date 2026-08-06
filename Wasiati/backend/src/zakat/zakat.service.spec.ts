import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ZakatService } from './zakat.service';

const config = (over: Record<string, string> = {}) =>
  ({ get: (k: string) => ({ ZAKAT_GOLD_PRICE_PER_GRAM_SAR: '50000', ...over })[k] }) as unknown as ConfigService;

/**
 * The live feed, as ZakatService sees it. `null` — the default in this file — is a dead
 * or stale feed, which exercises the env fallback these tests were originally written
 * against. Passing a number exercises live-first.
 *
 * Keyed to SAR — the currency every user in this file resolves to — NOT to whatever
 * argument arrives. A double that ignored its currency argument would keep passing if
 * the service regressed to looking up a hardcoded 'USD' (or the asset's currency), and
 * a wrong-currency gold price is a wrong nisāb in a different unit entirely.
 */
const gold = (liveMinor: number | null = null) =>
  ({
    livePricePerGramMinor: async (currency: string) => (currency === 'SAR' ? liveMinor : null),
  }) as any;

/** Constructor sugar so 12 existing call sites stay one line each. */
const service = (prisma: any, cfg: ConfigService, liveMinor: number | null = null) =>
  new ZakatService(prisma, cfg, gold(liveMinor));

function makeDb(opts: { assets?: any[]; user?: any; setting?: { value: string } | null } = {}) {
  const settings = new Map<string, any>();
  if (opts.setting) settings.set('zakat.charityUrl', { key: 'zakat.charityUrl', ...opts.setting });

  return {
    settings,
    prisma: {
      user: {
        findUnique: async () => opts.user ?? { id: 'u1', region: 'KSA', hawlDay: null, hawlMonth: null },
        update: async ({ data }: any) => ({ ...data }),
      },
      asset: { findMany: async () => opts.assets ?? [] },
      appSetting: {
        findUnique: async ({ where }: any) => settings.get(where.key) ?? null,
        upsert: async ({ where, create, update }: any) => {
          const existing = settings.get(where.key);
          const row = existing ? { ...existing, ...update } : create;
          settings.set(where.key, row);
          return row;
        },
      },
    } as any,
  };
}

describe('ZakatService', () => {
  describe('gold price / niṣāb', () => {
    it('REFUSES to estimate without a configured gold price — never guesses the niṣāb', async () => {
      const db = makeDb();
      const svc = service(db.prisma, config({ ZAKAT_GOLD_PRICE_PER_GRAM_SAR: undefined as any }));
      await expect(svc.estimate('u1')).rejects.toThrow(ServiceUnavailableException);
    });

    it('rejects a nonsense gold price rather than computing with it', async () => {
      const db = makeDb();
      for (const bad of ['0', '-1', 'abc']) {
        const svc = service(db.prisma, config({ ZAKAT_GOLD_PRICE_PER_GRAM_SAR: bad }));
        await expect(svc.estimate('u1')).rejects.toThrow(ServiceUnavailableException);
      }
    });
  });

  describe('gold price precedence — live first, env as manual fallback', () => {
    const CASH = [{ type: 'CASH', estimatedValue: '50000.00', currency: 'SAR' }];

    it('a FRESH live price wins over the env value', async () => {
      // live SAR 400.00/g vs env SAR 500.00/g: nisāb = 85 × live.
      const r = await service(makeDb({ assets: CASH }).prisma, config(), 40_000).estimate('u1');
      expect(r.nisabMinor).toBe(85 * 40_000);
    });

    it('a dead/stale feed falls back to the env value — the estimate stays up', async () => {
      const r = await service(makeDb({ assets: CASH }).prisma, config(), null).estimate('u1');
      expect(r.nisabMinor).toBe(85 * 50_000);
    });

    it('dead feed AND no env = 503, never a guess', async () => {
      const svc = service(makeDb().prisma, config({ ZAKAT_GOLD_PRICE_PER_GRAM_SAR: undefined as any }), null);
      await expect(svc.estimate('u1')).rejects.toThrow(ServiceUnavailableException);
    });
  });

  describe('estimate', () => {
    it('totals the user’s assets in their own currency and flags itself as an estimate', async () => {
      const db = makeDb({
        assets: [
          { type: 'CASH', estimatedValue: '50000.00', currency: 'SAR' },
          { type: 'CRYPTO', estimatedValue: '999999.00', currency: 'SAR' },
        ],
      });
      const svc = service(db.prisma, config());
      const r = await svc.estimate('u1');

      expect(r.currency).toBe('SAR');
      expect(r.zakatableTotalMinor).toBe(5_000_000);
      expect(r.zakatDueMinor).toBe(125_000); // SAR 1,250
      expect(r.excluded[0].type).toBe('CRYPTO');
      expect(r.isEstimate).toBe(true);
    });

    it('treats an asset with no currency as being in the user’s currency', async () => {
      const db = makeDb({ assets: [{ type: 'CASH', estimatedValue: '50000.00', currency: null }] });
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.zakatableTotalMinor).toBe(5_000_000);
    });

    it('skips assets with no recorded value rather than treating them as zero-worth', async () => {
      const db = makeDb({
        assets: [
          { type: 'CASH', estimatedValue: null, currency: 'SAR' },
          { type: 'GOLD', estimatedValue: '50000.00', currency: 'SAR' },
        ],
      });
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.categories).toHaveLength(1);
      expect(r.categories[0].type).toBe('GOLD');
    });

    it('reports the ḥawl when set', async () => {
      const db = makeDb({ user: { id: 'u1', region: 'KSA', hawlDay: 15, hawlMonth: 9 } });
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.hawl).toEqual({ day: 15, month: 9 });
    });
  });

  describe('"Pay your zakah" is gated on a published charity link', () => {
    it('returns no link when none is published — so no button renders', async () => {
      const db = makeDb();
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.charityUrl).toBeNull();
    });

    it('returns the link once an admin publishes one', async () => {
      const db = makeDb({ setting: { value: 'https://charity.example/zakat' } });
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.charityUrl).toBe('https://charity.example/zakat');
    });

    it('treats a blank published value as no link', async () => {
      const db = makeDb({ setting: { value: '   ' } });
      const r = await service(db.prisma, config()).estimate('u1');
      expect(r.charityUrl).toBeNull();
    });

    it('REFUSES a plain-http charity link — we are sending users to hand over money', async () => {
      const svc = service(makeDb().prisma, config());
      await expect(svc.setCharityUrl('http://charity.example', 'admin1')).rejects.toThrow(BadRequestException);
    });

    it('accepts https, and clearing it', async () => {
      const svc = service(makeDb().prisma, config());
      expect(await svc.setCharityUrl('https://charity.example', 'admin1')).toEqual({
        url: 'https://charity.example',
      });
      expect(await svc.setCharityUrl('', 'admin1')).toEqual({ url: null });
    });
  });

  describe('ḥawl', () => {
    it('rejects a Gregorian-looking date (day 31)', async () => {
      const svc = service(makeDb().prisma, config());
      await expect(svc.setHawl('u1', 31, 1)).rejects.toThrow(/Hijri/);
    });

    it('stores a valid Hijri day and month', async () => {
      const svc = service(makeDb().prisma, config());
      expect(await svc.setHawl('u1', 10, 12)).toEqual({ hawlDay: 10, hawlMonth: 12 });
    });
  });
});
