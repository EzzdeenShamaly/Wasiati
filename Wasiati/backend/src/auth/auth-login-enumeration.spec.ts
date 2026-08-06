import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';

/**
 * User-enumeration timing side channel on POST /auth/login.
 *
 * The body/status are already identical for a missing account and a wrong password
 * (401 {"message":"Invalid credentials."}). The leak was TIMING: validatePassword
 * used to `throw` before hashing when the account did not exist, so a missing email
 * returned in ~5ms while an existing one paid ~300ms for bcrypt.compare — a ~60x
 * delta that reveals which emails have accounts. The fix runs a dummy bcrypt.compare
 * on the not-found path so both paths cost the same.
 */
function makeService(user: any) {
  const prisma: any = { user: { findUnique: jest.fn().mockResolvedValue(user) } };
  const otp: any = { issue: jest.fn() };
  const tokens: any = {
    issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }),
  };
  const recovery: any = {};
  return { svc: new AuthService(prisma, otp, tokens, recovery, new TotpService({ get: () => 'x'.repeat(48) } as any), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any), prisma };
}

describe('AuthService.validatePassword — login user-enumeration timing side channel', () => {
  afterEach(() => jest.restoreAllMocks());

  it('runs a bcrypt comparison even when the account does not exist (no early-out before hashing)', async () => {
    const compare = jest.spyOn(bcrypt, 'compare');
    const { svc } = makeService(null); // no such user

    await expect(
      svc.validatePassword({ email: 'ghost@rt.test', password: 'whatever' } as any),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    // The regression: the not-found path must still spend a bcrypt.compare. If this is
    // 0, the endpoint returns ~instantly for missing accounts and the timing channel is
    // back.
    expect(compare).toHaveBeenCalledTimes(1);
  });

  it('an existing account with a wrong password also runs exactly one comparison', async () => {
    const compare = jest.spyOn(bcrypt, 'compare');
    const existing = {
      id: 'u1',
      email: 'victim@rt.test',
      region: 'US',
      role: 'USER',
      passwordHash: await bcrypt.hash('correct-horse', 12),
      mfaEnabled: false,
      phone: null,
    };
    compare.mockClear();
    const { svc } = makeService(existing);

    await expect(
      svc.validatePassword({ email: 'victim@rt.test', password: 'not-the-password' } as any),
    ).rejects.toBeInstanceOf(UnauthorizedException);

    // Same number of expensive comparisons as the missing-account path above (1), so
    // the two are indistinguishable by work performed.
    expect(compare).toHaveBeenCalledTimes(1);
  });

  it('returns an identical error (message + status) for a missing account and a wrong password', async () => {
    const existing = {
      id: 'u1',
      email: 'victim@rt.test',
      region: 'US',
      role: 'USER',
      passwordHash: await bcrypt.hash('correct-horse', 12),
      mfaEnabled: false,
      phone: null,
    };

    const missing = makeService(null);
    const wrong = makeService(existing);

    const missingErr = await missing.svc
      .validatePassword({ email: 'ghost@rt.test', password: 'x' } as any)
      .catch((e) => e);
    const wrongErr = await wrong.svc
      .validatePassword({ email: 'victim@rt.test', password: 'not-it' } as any)
      .catch((e) => e);

    expect(missingErr).toBeInstanceOf(UnauthorizedException);
    expect(wrongErr).toBeInstanceOf(UnauthorizedException);
    expect(missingErr.message).toBe(wrongErr.message);
    expect(missingErr.getStatus()).toBe(wrongErr.getStatus());
  });
});
