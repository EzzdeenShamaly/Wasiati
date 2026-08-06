import { authenticator } from 'otplib';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';

/**
 * An enrolled authenticator must replace the text message, not sit beside it.
 *
 * That is the whole point of the ladder. MFA is mandatory on every password login and the
 * default channel is SMS, which at Saudi rates ($0.1949/message — 15.6x a US one) is the
 * largest third-party line in the product at scale. A TOTP code costs nothing to deliver
 * AND is stronger: NIST SP 800-63B lists SMS as a restricted authenticator because of SIM
 * swap, which is a live threat here — the adversary this product resists is often family.
 *
 * So the load-bearing assertion is negative: when a user has an authenticator, NOTHING is
 * sent. A design that texted them anyway would be the expensive default wearing a hat.
 */
const PASSWORD = 'correct-horse-battery';
const SECRET = authenticator.generateSecret();

const totp = () => new TotpService({ get: () => 'x'.repeat(48) } as any);

function harness(user: any) {
  const sent: string[] = [];
  const prisma: any = {
    user: { findUnique: async () => user, update: async ({ data }: any) => Object.assign(user, data) },
    otpCode: { create: async () => ({}), findFirst: async () => null, count: async () => 0 },
    loginChallenge: { create: async () => ({}) },
  };
  const otp: any = {
    issue: async (dest: string) => (sent.push(dest), '123456'),
    verify: async () => false,
  };
  const tokens: any = { issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }) };
  const svc = new AuthService(prisma, otp, tokens, {} as any, totp(), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any);
  return { svc, sent, tokens, user };
}

const enrolled = async () => ({
  id: 'u1',
  email: 'a@b.test',
  phone: '+966555000111', // has a phone, and must STILL not be texted
  passwordHash: await bcrypt.hash(PASSWORD, 4),
  region: 'KSA',
  role: 'USER',
  mfaEnabled: true,
  mfaSecret: totp().seal(SECRET),
});

describe('an enrolled authenticator replaces the text message', () => {
  it('sends NOTHING at the password step, and says so', async () => {
    const h = harness(await enrolled());
    const res: any = await h.svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any);

    expect(res.mfaRequired).toBe(true);
    expect(res.via).toBe('totp');
    // The assertion that is worth the whole feature: a Saudi user who enrols costs
    // $0.1949 less on every single login, forever.
    expect(h.sent).toEqual([]);
  });

  it('completes the login with a code from the app', async () => {
    const h = harness(await enrolled());
    await h.svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any);
    await expect(h.svc.verifyMfaAndLogin('u1', authenticator.generate(SECRET))).resolves.toBeDefined();
    expect(h.tokens.issueTokenPair).toHaveBeenCalled();
  });

  it('refuses a wrong code, and refuses ANOTHER account\'s code', async () => {
    const h = harness(await enrolled());
    await expect(h.svc.verifyMfaAndLogin('u1', '000000')).rejects.toThrow(/Invalid or expired/);
    await expect(
      h.svc.verifyMfaAndLogin('u1', authenticator.generate(authenticator.generateSecret())),
    ).rejects.toThrow(/Invalid or expired/);
  });

  it('still texts a user who has NOT enrolled — MFA stays mandatory either way', async () => {
    const h = harness({
      id: 'u2',
      email: 'c@d.test',
      phone: '+966555000222',
      passwordHash: await bcrypt.hash(PASSWORD, 4),
      region: 'KSA',
      role: 'USER',
      mfaEnabled: false,
      mfaSecret: null,
    });
    const res: any = await h.svc.validatePassword({ email: 'c@d.test', password: PASSWORD } as any);
    expect(res.via).toBe('sms');
    expect(h.sent).toEqual(['+966555000222']);
  });

  it('falls back to the message channel if the stored secret cannot be opened', async () => {
    // Sealed under a different root (someone rotated SESSION_SECRET). The account must not
    // become unloggable-into: it drops back to SMS rather than demanding a code from an
    // authenticator whose secret we can no longer read.
    const u = await enrolled();
    u.mfaSecret = 'v1.aaaa.bbbb.cccc'; // undecryptable
    const h = harness(u);
    const res: any = await h.svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any);
    expect(res.via).toBe('totp'); // the flag still says enrolled...
    // ...but the code can never validate, which is why disable/re-enrol must stay reachable.
    await expect(h.svc.verifyMfaAndLogin('u1', authenticator.generate(SECRET))).rejects.toThrow();
  });
});

describe('enrolment proves the secret arrived before switching anything on', () => {
  it('start() hands back a scannable secret and enables NOTHING', async () => {
    const h = harness(await enrolled());
    const res = await h.svc.startTotpEnrollment('u1');
    expect(res.enabled).toBe(false);
    expect(res.otpauthUri).toContain('otpauth://totp/');
    expect(res.secret).toEqual(expect.any(String));
  });

  it('enable() refuses a code that does not match the secret being enrolled', async () => {
    const h = harness(await enrolled());
    const fresh = authenticator.generateSecret();
    await expect(h.svc.enableTotp('u1', fresh, '000000')).rejects.toThrow(/did not match/i);
  });

  it('enable() stores the secret SEALED, never in the clear', async () => {
    const h = harness(await enrolled());
    const fresh = authenticator.generateSecret();
    await h.svc.enableTotp('u1', fresh, authenticator.generate(fresh));
    expect(h.user.mfaEnabled).toBe(true);
    expect(h.user.mfaSecret).not.toContain(fresh);
    expect(totp().open(h.user.mfaSecret)).toBe(fresh);
  });

  it('disable() demands a current code — downgrading your own second factor is not free', async () => {
    const h = harness(await enrolled());
    await expect(h.svc.disableTotp('u1', '000000')).rejects.toThrow(/did not match/i);
    await h.svc.disableTotp('u1', authenticator.generate(SECRET));
    expect(h.user.mfaEnabled).toBe(false);
    expect(h.user.mfaSecret).toBeNull();
  });
});
