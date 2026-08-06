import { BadRequestException } from '@nestjs/common';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';

/**
 * Residency is derived from the DECLARED ADDRESS COUNTRY, not from the client's
 * `region` field.
 *
 * The old check compared `dto.region` — which the Flutter client fills from its own
 * build-time constant — against the deployment's region: the deployment comparing
 * itself to itself. It could never fire in the field, so a Saudi resident signing up
 * on the US build was silently filed as a US user, permanently (region is immutable
 * by omission — nothing ever writes it again).
 *
 * These pin the new rule: countryToRegion(addressCountry) decides the market, the
 * SERVED_REGIONS membership check decides whether THIS deployment may hold it, and
 * dto.region is ignored even when it lies.
 */
function makeService(created: any[]) {
  const prisma: any = {
    user: {
      findUnique: async () => null, // no duplicate email
      create: async ({ data }: any) => {
        created.push(data);
        return { id: 'u1', ...data, role: 'USER' };
      },
    },
  };
  const otp: any = {};
  const tokens: any = {
    issueTokenPair: async (user: any) => ({ accessToken: 'a', refreshToken: 'r', user }),
  };
  const recovery: any = { issueEmailVerification: async () => undefined };
  return new AuthService(prisma, otp, tokens, recovery, new TotpService({ get: () => 'x'.repeat(48) } as any), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any);
}

/** A complete, valid US-shaped registration; tests override what they probe. */
const BASE = {
  email: 'reg-residency@test.dev',
  password: 'a-long-enough-password-123',
  region: 'US',
  phone: '+1 555 010 2030',
  addressLine1: '1 Main St',
  addressCity: 'Springfield',
  addressArea: 'MA',
  addressPostalCode: '01101',
  addressCountry: 'US',
};

describe('registration residency (derived from address country)', () => {
  const ORIGINAL = { ...process.env };
  afterEach(() => {
    process.env = { ...ORIGINAL };
  });

  it('refuses a Saudi resident on a deployment that does not serve KSA', async () => {
    process.env.REGION = 'US';
    delete process.env.SERVED_REGIONS; // serves only US
    const svc = makeService([]);

    await expect(
      svc.register({
        ...BASE,
        addressCountry: 'SA',
        addressArea: 'Riyadh',
        addressPostalCode: undefined, // postal code optional in KSA
        // The client CLAIMS to be a US signup — the lie the old check believed.
        region: 'US',
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('files a Saudi resident as KSA on the single launch stack, whatever the client sent', async () => {
    process.env.REGION = 'CA';
    process.env.SERVED_REGIONS = 'US,CA,KSA'; // the launch topology
    const created: any[] = [];
    const svc = makeService(created);

    await svc.register({
      ...BASE,
      addressCountry: 'SA',
      addressArea: 'Riyadh',
      addressPostalCode: undefined,
      phone: '+966 55 010 2030',
      region: 'US', // ignored
    } as any);

    expect(created[0].region).toBe('KSA'); // SAR pricing, Nafath rail — the truth
    expect(created[0].addressCountry).toBe('SA');
  });

  it('files an unlisted country as US — the catch-all market', async () => {
    process.env.REGION = 'CA';
    process.env.SERVED_REGIONS = 'US,CA,KSA';
    const created: any[] = [];
    const svc = makeService(created);

    await svc.register({ ...BASE, addressCountry: 'GB', addressPostalCode: 'SW1A 1AA', region: 'CA' } as any);

    expect(created[0].region).toBe('US');
  });

  it('a Canadian resident lands as CA even on a US build', async () => {
    process.env.REGION = 'CA';
    process.env.SERVED_REGIONS = 'US,CA,KSA';
    const created: any[] = [];
    const svc = makeService(created);

    await svc.register({
      ...BASE,
      addressCountry: 'CA',
      addressArea: 'QC',
      addressPostalCode: 'H2X 1Y4',
      region: 'US', // the US build's constant — ignored
    } as any);

    expect(created[0].region).toBe('CA');
  });
});
