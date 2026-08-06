import { HttpException, HttpStatus, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { AuthService, LOGIN_MFA_MAX_PER_WINDOW, LOGIN_MFA_COOLDOWN_MS } from './auth.service';
import { TotpService } from './totp.service';
import { OtpService } from './otp.service';

/**
 * POST /auth/login/resend-mfa — "my code never arrived".
 *
 * Until now the resend control on the MFA screen was wired to a countdown timer and
 * nothing else: no request was ever made, no code was ever issued, and a user whose code
 * was lost or expired could only abandon the login and start over.
 *
 * The endpoint that fixes that is authenticated by an OPAQUE CHALLENGE TOKEN minted at the
 * password step, and by nothing else. The request body carries no userId. That is the whole
 * security argument, and these tests are mostly about it:
 *
 *   - a userId IS NOT A CREDENTIAL. It is returned in login responses, sits in request
 *     bodies, logs and support screenshots, and POST /auth/login/verify-mfa already accepts
 *     it from anyone. Any resend design whose abuse ceiling is "whoever knows the userId"
 *     fails open the day one leaks — and on a will platform the person holding a victim's
 *     userId is plausibly a family member with device access, which is the exact adversary
 *     this product exists to resist.
 *   - because the request contains no identifier at all, there is nothing here to enumerate
 *     and an unauthenticated caller can cause ZERO messages to be sent.
 *   - and because everyone holding a valid token has already typed the correct password,
 *     the server can answer them TRUTHFULLY (sent / 429 / expired) without becoming an
 *     oracle. Truth to the authenticated, one flat 401 to everyone else.
 *
 * These run against a real OtpService over an in-memory store, so "a code was sent",
 * "the cap counted it" and "the new code verifies" are observed behaviour rather than
 * assertions about mocks.
 */

// --- in-memory Prisma ------------------------------------------------------

function memoryDb(users: any[]) {
  const otpCodes: any[] = [];
  const challenges: any[] = [];
  let n = 0;

  const matches = (row: any, where: any = {}) =>
    (where.id === undefined || row.id === where.id) &&
    (where.destination === undefined || row.destination === where.destination) &&
    (where.purpose === undefined || row.purpose === where.purpose) &&
    (where.consumedAt === undefined || row.consumedAt === where.consumedAt) &&
    (where.createdAt?.gte === undefined || row.createdAt >= where.createdAt.gte);

  const prisma: any = {
    user: {
      findUnique: async ({ where }: any) =>
        users.find((u) => (where.id ? u.id === where.id : u.email === where.email)) ?? null,
    },
    otpCode: {
      create: async ({ data }: any) => {
        const row = { id: `otp${++n}`, attempts: 0, consumedAt: null, createdAt: new Date(), ...data };
        otpCodes.push(row);
        return row;
      },
      findFirst: async ({ where }: any) =>
        otpCodes
          .filter((r) => matches(r, where))
          .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0] ?? null,
      count: async ({ where }: any) => otpCodes.filter((r) => matches(r, where)).length,
      update: async ({ where, data }: any) => Object.assign(otpCodes.find((r) => r.id === where.id), data),
      updateMany: async ({ where, data }: any) => {
        const hit = otpCodes.filter((r) => matches(r, where));
        hit.forEach((r) => Object.assign(r, data));
        return { count: hit.length };
      },
    },
    loginChallenge: {
      create: async ({ data }: any) => {
        const row = { id: `lc${++n}`, createdAt: new Date(), ...data };
        challenges.push(row);
        return row;
      },
      findUnique: async ({ where }: any) => challenges.find((c) => c.tokenHash === where.tokenHash) ?? null,
    },
  };
  return { prisma, otpCodes, challenges };
}

const PASSWORD = 'correct-horse-battery';
let passwordHash: string;

function harness(users: any[]) {
  const { prisma, otpCodes, challenges } = memoryDb(users);
  const notifications: any = {
    // sendSms/sendEmail return whether the message was actually dispatched (true). issue()
    // honours that boolean and throws when it is false, so the happy-path mocks report true.
    sendSms: jest.fn().mockResolvedValue(true),
    sendEmail: jest.fn().mockResolvedValue(true),
    sendWhatsapp: jest.fn().mockResolvedValue(undefined),
  };
  const config: any = { get: () => undefined }; // OTP_DEV_ECHO off — production shape
  const otp = new OtpService(prisma, notifications, config);
  const tokens: any = {
    issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }),
  };
  const svc = new AuthService(prisma, otp, tokens, {} as any, new TotpService({ get: () => 'x'.repeat(48) } as any), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any);
  return { svc, prisma, notifications, otpCodes, challenges, tokens };
}

/** Total messages dispatched across every channel. */
const sendCount = (n: any) => n.sendSms.mock.calls.length + n.sendEmail.mock.calls.length;

/** The code as the USER received it — read back out of the message body. */
function lastCode(n: any): string {
  const bodies = [...n.sendSms.mock.calls.map((c: any[]) => c[1]), ...n.sendEmail.mock.calls.map((c: any[]) => c[2])];
  const m = /\b(\d{6})\b/.exec(bodies[bodies.length - 1]);
  return m![1];
}

/** Moves stored codes into the past — the cooldown and the OTP TTL are both wall-clock. */
const ageCodes = (rows: any[], ms: number) =>
  rows.forEach((r) => {
    r.createdAt = new Date(r.createdAt.getTime() - ms);
    r.expiresAt = new Date(r.expiresAt.getTime() - ms);
  });

const PAST_COOLDOWN = LOGIN_MFA_COOLDOWN_MS + 1000;

const withPhone = () => ({ id: 'u1', email: 'a@b.test', phone: '+966555000111', passwordHash, region: 'KSA', role: 'USER' });
const phoneless = () => ({ id: 'u2', email: 'c@d.test', phone: null, passwordHash, region: 'KSA', role: 'USER' });

beforeAll(async () => {
  passwordHash = await bcrypt.hash(PASSWORD, 4); // low cost: these tests hash a lot
});

async function login(svc: AuthService, email: string): Promise<string> {
  const res: any = await svc.validatePassword({ email, password: PASSWORD } as any);
  return res.challengeToken;
}

// --- the destination invariant ---------------------------------------------

describe('a re-sent code goes where verify-mfa will look for it', () => {
  // Login MFA and will step-up have EACH shipped a version of the bug where a code was
  // emailed and then checked against the phone. Resend adds a third place for issue and
  // verify to disagree, so both channels are pinned end to end.

  it('texts the phone, and the new code verifies', async () => {
    const { svc, notifications, otpCodes, tokens } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    ageCodes(otpCodes, PAST_COOLDOWN);

    await svc.resendLoginMfa(token);

    expect(notifications.sendSms).toHaveBeenCalledTimes(2);
    expect(notifications.sendSms.mock.calls[1][0]).toBe('+966555000111');
    expect(notifications.sendEmail).not.toHaveBeenCalled();
    await svc.verifyMfaAndLogin('u1', lastCode(notifications));
    expect(tokens.issueTokenPair).toHaveBeenCalled();
  });

  it('emails a phoneless account, and the new code verifies', async () => {
    // `phone` is optional on User. A resend that assumed a phone would strand exactly the
    // accounts the email fallback exists for.
    const { svc, notifications, otpCodes, tokens } = harness([phoneless()]);
    const token = await login(svc, 'c@d.test');
    ageCodes(otpCodes, PAST_COOLDOWN);

    await svc.resendLoginMfa(token);

    expect(notifications.sendEmail).toHaveBeenCalledTimes(2);
    expect(notifications.sendEmail.mock.calls[1][0]).toBe('c@d.test');
    expect(notifications.sendSms).not.toHaveBeenCalled();
    await svc.verifyMfaAndLogin('u2', lastCode(notifications));
    expect(tokens.issueTokenPair).toHaveBeenCalled();
  });
});

// --- the anti-oracle property ----------------------------------------------

describe('every rejected token reads exactly the same', () => {
  it('unknown, expired and malformed all return one status and one message', async () => {
    const { svc, challenges, notifications, otpCodes } = harness([withPhone()]);
    const live = await login(svc, 'a@b.test');

    // A second, independently-minted challenge — an expired-but-real token is the one case
    // that could plausibly leak "this was genuine once". (Aged first: a second login inside
    // the cooldown is itself refused, which is the point of the suite below.)
    ageCodes(otpCodes, PAST_COOLDOWN);
    const expired = await login(svc, 'a@b.test');
    challenges.forEach((c) => (c.expiresAt = new Date(Date.now() - 1000)));

    const attempts = [
      'not-a-token-at-all',
      '',
      '../../etc/passwd',
      'a'.repeat(500),
      Buffer.from('u1').toString('base64url'), // a userId, dressed up as a token
      live, // real token, but its challenge row is now expired
      expired,
    ];

    const seen: string[] = [];
    for (const t of attempts) {
      await svc.resendLoginMfa(t as any).catch((e) => {
        expect(e).toBeInstanceOf(UnauthorizedException);
        expect(e.getStatus()).toBe(HttpStatus.UNAUTHORIZED);
        seen.push(e.message);
      });
    }

    expect(seen).toHaveLength(attempts.length);
    expect(new Set(seen).size).toBe(1); // the whole point
    // The two logins sent two codes; not one of these attempts sent a third.
    expect(sendCount(notifications)).toBe(2);
  });

  it('an unauthenticated caller cannot make it send anything, whoever they claim to be', async () => {
    // The pending-row / bare-userId alternatives fail here: anyone holding a leaked userId
    // could fire an SMS during every genuine login window.
    const { svc, notifications } = harness([withPhone()]);
    for (const guess of ['u1', 'a@b.test', '+966555000111', 'undefined', 'null']) {
      await expect(svc.resendLoginMfa(guess)).rejects.toBeInstanceOf(UnauthorizedException);
    }
    expect(sendCount(notifications)).toBe(0);
  });

  it('a challenge for a deleted user is not distinguishable from a bad token', async () => {
    const users = [withPhone()];
    const { svc, notifications } = harness(users);
    const token = await login(svc, 'a@b.test');
    users.length = 0;

    const bad = await svc.resendLoginMfa('garbage').catch((e) => e.message);
    const gone = await svc.resendLoginMfa(token).catch((e) => e.message);
    expect(gone).toBe(bad);
    expect(sendCount(notifications)).toBe(1); // only the original login's code
  });
});

// --- privilege separation ---------------------------------------------------

describe('the challenge token is not a session, and a session is not a challenge token', () => {
  // The reason this is an opaque row rather than a JWT: TokenService signs access tokens
  // with the single app SESSION_SECRET and JwtStrategy.validate accepts ANY payload signed
  // with it without checking a `typ` claim. A signed challenge JWT would therefore be one
  // forgotten guard away from being accepted as an access token. Opaque + separate table
  // makes that confusion structurally impossible; these pin that it stays impossible.

  const jwt = new JwtService({ secret: 'test-secret', signOptions: { algorithm: 'HS256' } });

  it('a challenge token is not a JWT, so JwtAuthGuard routes cannot accept it', async () => {
    const { svc } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    expect(token.includes('.')).toBe(false); // not even JWT-shaped
    expect(() => jwt.verify(token)).toThrow();
  });

  it('an access token is rejected by resend-mfa, and sends nothing', async () => {
    const { svc, notifications } = harness([withPhone()]);
    await login(svc, 'a@b.test');
    const access = jwt.sign({ sub: 'u1', email: 'a@b.test', region: 'KSA', role: 'USER' });
    await expect(svc.resendLoginMfa(access)).rejects.toBeInstanceOf(UnauthorizedException);
    expect(sendCount(notifications)).toBe(1);
  });
});

// --- the limits -------------------------------------------------------------

describe('per-destination limits, enforced before anything is sent', () => {
  it('a resend inside the cooldown is refused and no message goes out', async () => {
    const { svc, notifications } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');

    await expect(svc.resendLoginMfa(token)).rejects.toMatchObject({
      status: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(sendCount(notifications)).toBe(1); // the login's code, and only that
  });

  it('the cooldown lifts, and the same token still works', async () => {
    // The token is not consumed by a resend: one challenge covers the whole 15 minutes,
    // because a user who needs two codes is a normal user.
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    ageCodes(otpCodes, PAST_COOLDOWN);
    await expect(svc.resendLoginMfa(token)).resolves.toEqual({ sent: true });
    ageCodes(otpCodes, PAST_COOLDOWN);
    await expect(svc.resendLoginMfa(token)).resolves.toEqual({ sent: true });
    expect(sendCount(notifications)).toBe(3);
  });

  it(`stops at ${LOGIN_MFA_MAX_PER_WINDOW} codes an hour, counting the one login itself sent`, async () => {
    // The cap lives in the helper BOTH call sites use. If resend had its own private
    // counter, an attacker holding the password would simply alternate between the two
    // endpoints — which is why the count is over OtpCode rows, not over requests.
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test'); // issue #1

    for (let i = 2; i <= LOGIN_MFA_MAX_PER_WINDOW; i++) {
      ageCodes(otpCodes, PAST_COOLDOWN);
      await expect(svc.resendLoginMfa(token)).resolves.toEqual({ sent: true });
    }
    expect(sendCount(notifications)).toBe(LOGIN_MFA_MAX_PER_WINDOW);

    ageCodes(otpCodes, PAST_COOLDOWN); // past the cooldown, still over the cap
    await expect(svc.resendLoginMfa(token)).rejects.toMatchObject({ status: HttpStatus.TOO_MANY_REQUESTS });
    expect(sendCount(notifications)).toBe(LOGIN_MFA_MAX_PER_WINDOW);
  });

  it('the cap also stops a correct-password replay through POST /auth/login itself', async () => {
    // This hole predates the resend endpoint: /auth/login was throttled at 8/min/IP with no
    // per-destination limit at all, so anyone with one victim's password could pump SMS at
    // their phone and rotate IPs past the throttle. Routing validatePassword through the
    // same helper is what closes it — a resend-only cap never could.
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    for (let i = 0; i < LOGIN_MFA_MAX_PER_WINDOW; i++) {
      await login(svc, 'a@b.test');
      ageCodes(otpCodes, PAST_COOLDOWN);
    }
    await expect(svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any)).rejects.toMatchObject({
      status: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(sendCount(notifications)).toBe(LOGIN_MFA_MAX_PER_WINDOW);
  });

  it('two spellings of one phone number share a single bucket', async () => {
    // Counting the raw string would let '+966 555-000-111' and '+966555000111' each carry
    // their own allowance. Everything keys through otpDestinationKey for that reason.
    const user = { ...withPhone(), phone: '+966 555-000-111' };
    const { svc, prisma, notifications } = harness([user]);
    for (let i = 0; i < LOGIN_MFA_MAX_PER_WINDOW; i++) {
      await prisma.otpCode.create({
        data: { destination: '+966555000111', purpose: 'login_mfa', codeHash: 'x', expiresAt: new Date() },
      });
    }
    await expect(svc.validatePassword({ email: 'a@b.test', password: PASSWORD } as any)).rejects.toMatchObject({
      status: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(sendCount(notifications)).toBe(0);
  });

  it('the cooldown and the cap are indistinguishable to the caller', async () => {
    const { svc, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    const cooling = await svc.resendLoginMfa(token).catch((e: HttpException) => e.message);

    for (let i = 2; i <= LOGIN_MFA_MAX_PER_WINDOW; i++) {
      ageCodes(otpCodes, PAST_COOLDOWN);
      await svc.resendLoginMfa(token);
    }
    ageCodes(otpCodes, PAST_COOLDOWN);
    const capped = await svc.resendLoginMfa(token).catch((e: HttpException) => e.message);
    expect(capped).toBe(cooling);
  });
});

// --- honesty ----------------------------------------------------------------

describe('the response tells the truth about whether a code was sent', () => {
  // The always-200 pattern is correct for ANONYMOUS endpoints (password/forgot-code) and
  // wrong here. The client restarts its 30-second countdown on success; a { sent: true }
  // for a message that never went out would start a countdown for a code that never comes.

  it('reports sent only after the message is dispatched', async () => {
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    ageCodes(otpCodes, PAST_COOLDOWN);
    const before = sendCount(notifications);
    await expect(svc.resendLoginMfa(token)).resolves.toEqual({ sent: true });
    expect(sendCount(notifications)).toBe(before + 1);
  });

  it('a delivery failure surfaces as an error, never as sent:true', async () => {
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    ageCodes(otpCodes, PAST_COOLDOWN);
    notifications.sendSms.mockRejectedValueOnce(new Error('gateway down'));
    await expect(svc.resendLoginMfa(token)).rejects.toThrow('gateway down');
  });

  it('an SMS that reached nobody (returns false) also surfaces as an error, not sent:true', async () => {
    // The actual silent-failure case: an unconfigured transport RETURNS false rather than
    // throwing. Before this fix that returned { sent: true } and started the client's
    // countdown for a code that never comes. issue() now turns it into a real error.
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    ageCodes(otpCodes, PAST_COOLDOWN);
    notifications.sendSms.mockResolvedValueOnce(false);
    await expect(svc.resendLoginMfa(token)).rejects.toMatchObject({ status: HttpStatus.SERVICE_UNAVAILABLE });
  });
});

// --- response hygiene -------------------------------------------------------

describe('the response body carries no account detail', () => {
  it('returns exactly { sent: true } — no destination, no mask, no via', async () => {
    for (const user of [withPhone(), phoneless()]) {
      const { svc, otpCodes } = harness([user]);
      const token = await login(svc, user.email);
      ageCodes(otpCodes, PAST_COOLDOWN);
      const res = await svc.resendLoginMfa(token);

      expect(Object.keys(res)).toEqual(['sent']);
      const body = JSON.stringify(res);
      expect(body).not.toContain('via');
      expect(body).not.toContain(user.email);
      if (user.phone) expect(body).not.toContain('555');
      expect(body).not.toMatch(/\*|•/); // not even a masked contact
    }
  });
});

// --- the user story ---------------------------------------------------------

describe('the user whose code expired', () => {
  it('can re-send after the 10-minute code dies, because the challenge lives 15', async () => {
    // This is the entire reason the challenge TTL is longer than the OTP TTL. Had they
    // matched, the one person who needs resend — whose code just expired — would be the one
    // person locked out of it.
    const { svc, notifications, otpCodes, tokens } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    const firstCode = lastCode(notifications);

    ageCodes(otpCodes, 11 * 60 * 1000); // eleven minutes later: code dead, challenge alive

    await expect(svc.resendLoginMfa(token)).resolves.toEqual({ sent: true });
    const freshCode = lastCode(notifications);

    await svc.verifyMfaAndLogin('u1', freshCode);
    expect(tokens.issueTokenPair).toHaveBeenCalled();
    expect(freshCode).not.toBe(firstCode);
  });

  it('but not once the challenge itself has expired — they sign in again', async () => {
    const { svc, challenges, notifications } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    challenges.forEach((c) => (c.expiresAt = new Date(Date.now() - 1000)));
    await expect(svc.resendLoginMfa(token)).rejects.toBeInstanceOf(UnauthorizedException);
    expect(sendCount(notifications)).toBe(1);
  });

  it('verify only ever checks the newest code, so resends do not widen the guess space', async () => {
    // Each resend is a fresh code with a fresh attempt budget, but the old code stops being
    // checkable the moment a newer one exists — so the hourly cap bounds total guesses at
    // 5 codes x OTP_MAX_ATTEMPTS against a 10^6 space, not 5 live codes at once.
    const { svc, notifications, otpCodes } = harness([withPhone()]);
    const token = await login(svc, 'a@b.test');
    const stale = lastCode(notifications);
    ageCodes(otpCodes, PAST_COOLDOWN);
    await svc.resendLoginMfa(token);

    await expect(svc.verifyMfaAndLogin('u1', stale)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(svc.verifyMfaAndLogin('u1', lastCode(notifications))).resolves.toBeDefined();
  });
});
