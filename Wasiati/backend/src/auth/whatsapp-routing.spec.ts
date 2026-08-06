import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';
import { isSaudiPhone } from '../common/phone.util';

/**
 * Saudi login codes go over WhatsApp, not SMS.
 *
 * A Saudi SMS costs $0.1949 — 15.6x a US one, and the most expensive thing this product
 * does per login. The same message over WhatsApp is roughly $0.045: a ~77% cut on the
 * largest third-party line in the business, for users who have not enrolled an
 * authenticator. WhatsApp penetration in Saudi is near-universal, which is why the routing
 * is restricted to +966 rather than applied everywhere — elsewhere it would trade a small
 * saving for undeliverable logins.
 *
 * Two invariants matter as much as the routing itself: it stays INERT until a sender is
 * configured (so nothing changes in an environment without one), and the code still
 * verifies afterwards — the channel changes, the destination key does not.
 */
const PASSWORD = 'correct-horse-battery';
const KSA_PHONE = '+966555000111';
const US_PHONE = '+14155552671';

function harness({ phone, whatsapp }: { phone: string | null; whatsapp: boolean }) {
  const issued: { destination: string; channel?: string }[] = [];
  const user: any = {
    id: 'u1',
    email: 'a@b.test',
    phone,
    passwordHash: '',
    region: 'KSA',
    role: 'USER',
    mfaEnabled: false,
    mfaSecret: null,
  };
  const prisma: any = {
    user: { findUnique: async () => user, update: async ({ data }: any) => Object.assign(user, data) },
    otpCode: { create: async () => ({}), findFirst: async () => null, count: async () => 0 },
    loginChallenge: { create: async () => ({}) },
  };
  const otp: any = {
    whatsappAvailable: whatsapp,
    issue: async (destination: string, _p: string, _u: string, channel?: string) => {
      issued.push({ destination, channel });
      return '123456';
    },
    // Keyed off (destination, purpose) — NOT the channel — which is why a code sent over
    // WhatsApp verifies through the same path an SMS one does.
    verify: async (destination: string) => destination === phone,
  };
  const tokens: any = { issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }) };
  const recovery: any = { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) };
  const svc = new AuthService(prisma, otp, tokens, {} as any, new TotpService({ get: () => 'x'.repeat(48) } as any), recovery);
  return { svc, issued, user, tokens };
}

const login = async (svc: AuthService, user: any) => {
  user.passwordHash = await bcrypt.hash(PASSWORD, 4);
  return svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any) as any;
};

describe('isSaudiPhone', () => {
  it('recognises Saudi numbers in international and national form', () => {
    expect(isSaudiPhone('+966555000111')).toBe(true);
    expect(isSaudiPhone('00966555000111')).toBe(true);
    // National form needs the hint, which is how the app stores/normalises anyway.
    expect(isSaudiPhone('0555000111', 'KSA')).toBe(true);
  });

  it('does not mistake other countries for Saudi', () => {
    expect(isSaudiPhone(US_PHONE)).toBe(false);
    expect(isSaudiPhone('+447700900123')).toBe(false);
    expect(isSaudiPhone(null)).toBe(false);
    expect(isSaudiPhone('')).toBe(false);
  });
});

describe('channel routing', () => {
  it('sends a Saudi number over WHATSAPP once a sender is configured', async () => {
    const h = harness({ phone: KSA_PHONE, whatsapp: true });
    const res = await login(h.svc, h.user);
    expect(res.via).toBe('whatsapp');
    expect(h.issued).toEqual([{ destination: KSA_PHONE, channel: 'whatsapp' }]);
  });

  it('stays INERT with no sender configured — the expensive path is unchanged', async () => {
    // The saving must never come at the cost of a login that cannot be delivered.
    const h = harness({ phone: KSA_PHONE, whatsapp: false });
    const res = await login(h.svc, h.user);
    expect(res.via).toBe('sms');
    expect(h.issued[0].channel).toBe('sms');
  });

  it('leaves NON-Saudi numbers on SMS even with WhatsApp available', async () => {
    // Restricted on purpose: cheaper only where it is also reliably present.
    const h = harness({ phone: US_PHONE, whatsapp: true });
    const res = await login(h.svc, h.user);
    expect(res.via).toBe('sms');
  });

  it('still emails a phoneless account', async () => {
    const h = harness({ phone: null, whatsapp: true });
    const res = await login(h.svc, h.user);
    expect(res.via).toBe('email');
    expect(h.issued[0].destination).toBe('a@b.test');
  });

  it('a code sent over WhatsApp verifies — the channel changes, the key does not', async () => {
    const h = harness({ phone: KSA_PHONE, whatsapp: true });
    await login(h.svc, h.user);
    await expect(h.svc.verifyMfaAndLogin('u1', '123456')).resolves.toBeDefined();
    expect(h.tokens.issueTokenPair).toHaveBeenCalled();
  });

  it('an enrolled authenticator still outranks WhatsApp — free beats cheap', async () => {
    const h = harness({ phone: KSA_PHONE, whatsapp: true });
    const totp = new TotpService({ get: () => 'x'.repeat(48) } as any);
    h.user.mfaEnabled = true;
    h.user.mfaSecret = totp.seal(totp.generateSecret());
    const res = await login(h.svc, h.user);
    expect(res.via).toBe('totp');
    expect(h.issued).toEqual([]); // nothing sent at all
  });
});
