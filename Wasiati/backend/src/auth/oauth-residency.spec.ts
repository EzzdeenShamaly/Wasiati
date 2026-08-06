import { AuthService } from './auth.service';
import { TotpService } from './totp.service';

/**
 * OAuth signup must derive residency the same way a password signup does.
 *
 * `region` is IMMUTABLE and decides pricing currency, and which KYC rail a user gets
 * (Stripe Identity vs Nafath). register() stopped trusting the client's `region` field
 * precisely because the Flutter build sent its OWN region, which filed a Saudi resident as
 * a US user permanently. OAuth kept the older shape — tolerable while it only served
 * returning users, and not tolerable once it becomes the PRIMARY signup path, which is
 * exactly what promoting these buttons to the top of the signup screen does.
 */
function harness() {
  const created: any[] = [];
  const prisma: any = {
    user: {
      findUnique: async () => null, // always a new signup
      create: async ({ data }: any) => (created.push(data), { id: 'u1', role: 'USER', ...data }),
    },
  };
  const tokens: any = { issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }) };
  const recovery: any = { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) };
  const svc = new AuthService(
    prisma,
    {} as any,
    tokens,
    {} as any,
    new TotpService({ get: () => 'x'.repeat(48) } as any),
    recovery,
  );
  return { svc, created };
}

const signUp = (svc: AuthService, over: Record<string, unknown>) =>
  svc.loginWithOAuth({ email: 'a@b.test', providerId: 'g1', provider: 'GOOGLE' as any, ...over } as any);

describe('OAuth signup residency', () => {
  const realRegion = process.env.REGION;
  const realServed = process.env.SERVED_REGIONS;
  beforeEach(() => {
    process.env.REGION = 'US';
    process.env.SERVED_REGIONS = 'US,CA,KSA';
  });
  afterEach(() => {
    process.env.REGION = realRegion;
    process.env.SERVED_REGIONS = realServed;
  });

  it('derives the market from the stated COUNTRY, not the client\'s region claim', async () => {
    const h = harness();
    // The exact conflict: a Saudi resident whose client claims US. The country wins.
    await signUp(h.svc, { addressCountry: 'SA', region: 'US' });
    expect(h.created[0].region).toBe('KSA');
  });

  it('files a Canadian as CA, so they are priced in CAD rather than the build default', async () => {
    const h = harness();
    await signUp(h.svc, { addressCountry: 'CA' });
    expect(h.created[0].region).toBe('CA');
  });

  it('falls back to the client region when no country is sent, so older clients still work', async () => {
    const h = harness();
    await signUp(h.svc, { region: 'CA' });
    expect(h.created[0].region).toBe('CA');
  });

  it('falls back to the deployment region when neither is sent', async () => {
    const h = harness();
    await signUp(h.svc, {});
    expect(h.created[0].region).toBe('US');
  });

  it('still refuses a market this stack does not serve', async () => {
    process.env.SERVED_REGIONS = 'US';
    const h = harness();
    // A country outside SERVED_REGIONS must not create an account here, however it arrived.
    await expect(signUp(h.svc, { addressCountry: 'SA' })).rejects.toThrow();
    expect(h.created).toEqual([]);
  });

  it('marks the email verified — the provider already proved it', async () => {
    const h = harness();
    await signUp(h.svc, { addressCountry: 'US' });
    expect(h.created[0].emailVerified).toBe(true);
  });
});
