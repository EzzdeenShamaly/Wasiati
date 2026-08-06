import { Region } from '@prisma/client';
import { CatalogController } from './catalog.controller';
import { resolvePricingRegion } from '../common/geo.util';

/**
 * THE currency rule: what a member is billed in follows their ACCOUNT, not where
 * they are standing.
 *
 * The regression these pin: the catalog resolved its region from `?region=` or the
 * CF-IPCountry header and never looked at the signed-in user — so a Saudi member on
 * a US VPN (or anyone appending `?region=US`) was quoted USD instead of SAR. Both
 * inputs are client-controlled, which is fine for a visitor we cannot identify and
 * unacceptable for one we can.
 */
describe('pricing region — the account wins for a signed-in user', () => {
  describe('resolvePricingRegion (the rule itself)', () => {
    it('uses the ACCOUNT region and IGNORES a spoofed ?region=', () => {
      expect(
        resolvePricingRegion({
          accountRegion: Region.KSA,
          explicitRegion: 'US',
          req: { headers: { 'cf-ipcountry': 'US' } },
        }),
      ).toBe(Region.KSA);
    });

    it('uses the ACCOUNT region and IGNORES the geo header (the VPN case)', () => {
      expect(
        resolvePricingRegion({ accountRegion: Region.CA, req: { headers: { 'cf-ipcountry': 'GB' } } }),
      ).toBe(Region.CA);
    });

    it('falls back to an explicit ?region= for an ANONYMOUS visitor', () => {
      expect(resolvePricingRegion({ accountRegion: null, explicitRegion: 'CA' })).toBe(Region.CA);
    });

    it('falls back to geo-IP for an ANONYMOUS visitor', () => {
      expect(resolvePricingRegion({ req: { headers: { 'cf-ipcountry': 'SA' } } })).toBe(Region.KSA);
    });

    it('defaults an anonymous visitor with no signal at all to US', () => {
      expect(resolvePricingRegion({ req: { headers: {} } })).toBe(Region.US);
    });
  });

  describe('GET /pricing (the endpoint that regressed)', () => {
    const makeController = (accountRegion: Region | null) => {
      const seen: Region[] = [];
      const pricing: any = {
        accountRegion: async () => accountRegion,
        getCatalog: async (region: Region) => {
          seen.push(region);
          return { region, currency: 'X', plans: [], offers: [] };
        },
      };
      const promotions: any = { validate: async (_c: string, _t: any, region: Region) => ({ valid: true, region }) };
      return { controller: new CatalogController(pricing, promotions), seen };
    };

    it('a signed-in KSA user asking for ?region=US still gets SAR', async () => {
      const { controller, seen } = makeController(Region.KSA);
      const res = await controller.catalog(
        { headers: { 'cf-ipcountry': 'US' } } as any,
        { userId: 'u1' },
        'US', // the spoof
      );
      expect(seen).toEqual([Region.KSA]);
      expect(res.region).toBe(Region.KSA);
    });

    it('a signed-in KSA user browsing from a US IP still gets SAR', async () => {
      const { controller, seen } = makeController(Region.KSA);
      await controller.catalog({ headers: { 'cf-ipcountry': 'US' } } as any, { userId: 'u1' }, undefined);
      expect(seen).toEqual([Region.KSA]);
    });

    it('an ANONYMOUS visitor still falls back to geo', async () => {
      const { controller, seen } = makeController(null);
      await controller.catalog({ headers: { 'cf-ipcountry': 'CA' } } as any, undefined, undefined);
      expect(seen).toEqual([Region.CA]);
    });

    it('an ANONYMOUS visitor may still price-shop with ?region=', async () => {
      const { controller, seen } = makeController(null);
      await controller.catalog({ headers: {} } as any, undefined, 'CA');
      expect(seen).toEqual([Region.CA]);
    });

    it('a user id that resolves to no account degrades to geo rather than failing', async () => {
      const { controller, seen } = makeController(null);
      await controller.catalog({ headers: { 'cf-ipcountry': 'SA' } } as any, { userId: 'ghost' }, undefined);
      expect(seen).toEqual([Region.KSA]);
    });
  });

  describe('POST /pricing/validate-promo — the same rule, so the preview cannot lie', () => {
    it('previews a signed-in KSA user against KSA even when the body says US', async () => {
      const checked: Region[] = [];
      const pricing: any = { accountRegion: async () => Region.KSA };
      const promotions: any = {
        validate: async (_code: string, _tier: any, region: Region) => {
          checked.push(region);
          return { valid: true };
        },
      };
      const controller = new CatalogController(pricing, promotions);

      await controller.validatePromo({ headers: {} } as any, { userId: 'u1' }, {
        code: 'WASIATI30',
        region: Region.US,
      } as any);

      expect(checked).toEqual([Region.KSA]);
    });
  });
});
