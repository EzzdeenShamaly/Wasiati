import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';

/**
 * A password is never sufficient on its own (owner decision, 20 Jul 2026).
 *
 * The second factor used to be gated on `user.mfaEnabled && user.phone`, and NOTHING in the
 * product could set mfaEnabled to true — no endpoint, no settings control, no seed. Grep it:
 * the only writes are the schema default and test fixtures. So the entire MFA branch was
 * dead code, and a single reusable password was the only thing between an attacker and
 * someone's will. Credential stuffing does not need a breach of US to work.
 *
 * Passkeys and OAuth are exempt by design: both carry their own possession/strong-auth
 * proof and neither comes through validatePassword.
 */
function makeService(user: any) {
  const prisma: any = {
    user: { findUnique: jest.fn().mockResolvedValue(user) },
    // The per-destination cooldown/cap counters AuthService.issueLoginMfa reads before it
    // sends. Empty here: these tests are about which channel is chosen, not the limits
    // (login-mfa-resend.spec.ts pins those).
    otpCode: {
      findFirst: jest.fn().mockResolvedValue(null),
      count: jest.fn().mockResolvedValue(0),
    },
    loginChallenge: { create: jest.fn().mockResolvedValue({ id: 'lc1' }) },
  };
  const otp: any = { issue: jest.fn().mockResolvedValue({ id: 'otp1' }), verify: jest.fn().mockResolvedValue(true) };
  const tokens: any = {
    issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }),
  };
  const recovery: any = {};
  return { svc: new AuthService(prisma, otp, tokens, recovery, new TotpService({ get: () => 'x'.repeat(48) } as any), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any), prisma, otp, tokens };
}

const withPhone = {
  id: 'u1',
  email: 'a@b.test',
  phone: '+966555000111',
  passwordHash: 'hash',
  mfaEnabled: false,
};
const phoneless = { id: 'u2', email: 'c@d.test', phone: null, passwordHash: 'hash', mfaEnabled: false };

describe('a correct password alone never issues a session', () => {
  beforeEach(() => jest.spyOn(bcrypt, 'compare').mockResolvedValue(true as never));
  afterEach(() => jest.restoreAllMocks());

  it('challenges even though mfaEnabled is FALSE — the flag no longer gates it', async () => {
    // This is the regression. mfaEnabled: false was every real account, so the old
    // condition made the second factor unreachable for the entire user base.
    const { svc, tokens, otp } = makeService(withPhone);
    const res: any = await svc.validatePassword({ email: 'a@b.test', password: 'right' } as any);
    expect(res.mfaRequired).toBe(true);
    expect(tokens.issueTokenPair).not.toHaveBeenCalled();
    expect(otp.issue).toHaveBeenCalledWith('+966555000111', 'login_mfa', 'u1', 'sms');
  });

  it('emails the code when the account has no phone, instead of locking them out', async () => {
    // `phone` is optional on User and the old gate REQUIRED it, so making MFA mandatory
    // without this fallback would have shut every phoneless account out of its own will.
    const { svc, otp } = makeService(phoneless);
    const res: any = await svc.validatePassword({ email: 'c@d.test', password: 'right' } as any);
    expect(res.mfaRequired).toBe(true);
    expect(res.via).toBe('email');
    expect(otp.issue).toHaveBeenCalledWith('c@d.test', 'login_mfa', 'u2', 'email');
  });

  it('tells the client WHICH channel, so the prompt does not say "SMS" over an email', async () => {
    const { svc } = makeService(withPhone);
    const res: any = await svc.validatePassword({ email: 'a@b.test', password: 'right' } as any);
    expect(res.via).toBe('sms');
  });

  it('hands back a challenge token, so the code can be re-sent without the password again', async () => {
    // AuthAwaitingMfa deliberately does NOT keep the password client-side, so re-calling
    // /auth/login to re-trigger the code is not available. This token is what replaces it.
    const { svc, prisma } = makeService(withPhone);
    const res: any = await svc.validatePassword({ email: 'a@b.test', password: 'right' } as any);
    expect(typeof res.challengeToken).toBe('string');
    expect(res.challengeToken.length).toBeGreaterThan(20);
    // Only the hash is stored; the raw value exists in the response and nowhere else.
    const stored = prisma.loginChallenge.create.mock.calls[0][0].data;
    expect(stored.tokenHash).not.toBe(res.challengeToken);
    expect(stored.userId).toBe('u1');
  });

  it('a wrong password never reaches the challenge — no code is sent', async () => {
    jest.spyOn(bcrypt, 'compare').mockResolvedValue(false as never);
    const { svc, otp } = makeService(withPhone);
    await expect(
      svc.validatePassword({ email: 'a@b.test', password: 'wrong' } as any),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(otp.issue).not.toHaveBeenCalled();
  });
});

describe('the second step verifies against the channel the code was ISSUED to', () => {
  afterEach(() => jest.restoreAllMocks());

  it('verifies a phoneless account against its EMAIL', async () => {
    // verifyMfaAndLogin used to reject any user without a phone outright, so a phoneless
    // account would have been emailed a code and then refused when it typed it in.
    const { svc, otp, tokens } = makeService(phoneless);
    await svc.verifyMfaAndLogin('u2', '123456');
    expect(otp.verify).toHaveBeenCalledWith('c@d.test', 'login_mfa', '123456');
    expect(tokens.issueTokenPair).toHaveBeenCalled();
  });

  it('verifies a phone account against its PHONE', async () => {
    const { svc, otp } = makeService(withPhone);
    await svc.verifyMfaAndLogin('u1', '123456');
    expect(otp.verify).toHaveBeenCalledWith('+966555000111', 'login_mfa', '123456');
  });

  it('a bad code issues no session', async () => {
    const { svc, otp, tokens } = makeService(withPhone);
    otp.verify.mockResolvedValue(false);
    await expect(svc.verifyMfaAndLogin('u1', '000000')).rejects.toBeInstanceOf(UnauthorizedException);
    expect(tokens.issueTokenPair).not.toHaveBeenCalled();
  });

  it('an unknown user id issues no session', async () => {
    const { svc, tokens } = makeService(null);
    await expect(svc.verifyMfaAndLogin('nope', '123456')).rejects.toBeInstanceOf(UnauthorizedException);
    expect(tokens.issueTokenPair).not.toHaveBeenCalled();
  });
});
