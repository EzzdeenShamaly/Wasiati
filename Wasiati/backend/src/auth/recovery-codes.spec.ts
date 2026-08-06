import * as bcrypt from 'bcryptjs';
import { createHash } from 'crypto';
import { AuthService } from './auth.service';
import { TotpService } from './totp.service';
import { RECOVERY_CODE_COUNT, RecoveryCodesService } from './recovery-codes.service';

/**
 * Backup codes are the reason it is safe to make an authenticator the preferred factor.
 *
 * On a will platform "I lost my phone" cannot mean "my family cannot reach my will", and
 * there is no support path that could verify a locked-out owner without re-creating the
 * exact impersonation risk MFA exists to stop. So the properties that matter are: a code
 * works when the primary factor is completely unreachable, it works EXACTLY once, and a
 * stolen database contains nothing that can be replayed.
 */

/** An in-memory RecoveryCode table with the conditional-update semantics the real one has. */
function memoryCodes() {
  const rows: any[] = [];
  const table = {
        deleteMany: async ({ where }: any) => {
          const keep = rows.filter((r) => r.userId !== where.userId);
          const n = rows.length - keep.length;
          rows.length = 0;
          rows.push(...keep);
          return { count: n };
        },
        createMany: async ({ data }: any) => (rows.push(...data), { count: data.length }),
        count: async ({ where }: any) =>
          rows.filter(
            (r) => r.userId === where.userId && (where.usedAt === undefined || r.usedAt == (where.usedAt ?? null)),
          ).length,
        updateMany: async ({ where, data }: any) => {
          // Mirrors the real guard: the row must still be unused for the update to land.
          const hit = rows.filter(
            (r) => r.userId === where.userId && r.codeHash === where.codeHash && r.usedAt == null,
          );
          hit.forEach((r) => Object.assign(r, data));
          return { count: hit.length };
        },
  };
  // regenerate() runs inside a transaction; hand the callback the SAME table so the
  // delete-then-create really is observed as one replacement.
  const prisma = { recoveryCode: table, $transaction: async (fn: any) => fn({ recoveryCode: table }) } as any;
  return { rows, prisma };
}

const makeService = () => {
  const mem = memoryCodes();
  return { svc: new RecoveryCodesService(mem.prisma), rows: mem.rows };
};

describe('RecoveryCodesService', () => {
  it('issues a full set, and returns the plaintext exactly once', async () => {
    const { svc, rows } = makeService();
    const { codes } = await svc.regenerate('u1');
    expect(codes).toHaveLength(RECOVERY_CODE_COUNT);
    expect(new Set(codes).size).toBe(RECOVERY_CODE_COUNT); // no duplicates
    // A stolen database must not contain anything replayable.
    for (const c of codes) {
      expect(rows.some((r) => r.codeHash === c)).toBe(false);
      expect(rows.some((r) => r.codeHash === createHash('sha256').update(c.replace(/-/g, '')).digest('hex'))).toBe(true);
    }
  });

  it('uses only unambiguous characters — these are read off paper under stress', async () => {
    const { svc } = makeService();
    const { codes } = await svc.regenerate('u1');
    // No I, L, O or U: every one of them is a support ticket when hand-copied.
    for (const c of codes) expect(c).toMatch(/^[0-9A-HJ-KM-NP-TV-Z]{4}-[0-9A-HJ-KM-NP-TV-Z]{4}-[0-9A-HJ-KM-NP-TV-Z]{4}$/);
  });

  it('accepts a code however it was re-typed — lower case, no dashes, stray spaces', async () => {
    const { svc } = makeService();
    const { codes } = await svc.regenerate('u1');
    const typed = ` ${codes[0].toLowerCase().replace(/-/g, '')} `;
    await expect(svc.consume('u1', typed)).resolves.toBe(true);
  });

  it('spends a code EXACTLY once', async () => {
    const { svc } = makeService();
    const { codes } = await svc.regenerate('u1');
    await expect(svc.consume('u1', codes[0])).resolves.toBe(true);
    await expect(svc.consume('u1', codes[0])).resolves.toBe(false);
  });

  it('holds single-use under a RACE, not just in sequence', async () => {
    const { svc } = makeService();
    const { codes } = await svc.regenerate('u1');
    const results = await Promise.all([svc.consume('u1', codes[0]), svc.consume('u1', codes[0])]);
    expect(results.filter(Boolean)).toHaveLength(1);
  });

  it('refuses another account\'s code, even though the hash is globally unique', async () => {
    const { svc } = makeService();
    const mine = (await svc.regenerate('u1')).codes;
    await svc.regenerate('u2');
    await expect(svc.consume('u2', mine[0])).resolves.toBe(false);
    // ...and it is still spendable by its rightful owner.
    await expect(svc.consume('u1', mine[0])).resolves.toBe(true);
  });

  it('regenerating INVALIDATES the previous set', async () => {
    const { svc } = makeService();
    const first = (await svc.regenerate('u1')).codes;
    const second = (await svc.regenerate('u1')).codes;
    // Someone who regenerates because they think their codes leaked must actually have
    // retired the leaked ones.
    await expect(svc.consume('u1', first[0])).resolves.toBe(false);
    await expect(svc.consume('u1', second[0])).resolves.toBe(true);
  });

  it('reports what remains, and flags when it is running low', async () => {
    const { svc } = makeService();
    const { codes } = await svc.regenerate('u1');
    expect(await svc.status('u1')).toMatchObject({ remaining: 10, total: 10, low: false });
    for (const c of codes.slice(0, 8)) await svc.consume('u1', c);
    // Running out unnoticed is the lockout this flag exists to prevent.
    expect(await svc.status('u1')).toMatchObject({ remaining: 2, low: true });
  });

  it('ignores anything that is not code-shaped, without a database round trip', async () => {
    const { svc } = makeService();
    await svc.regenerate('u1');
    // A 6-digit TOTP reaches consume() on every login; it must be cheap to reject.
    await expect(svc.consume('u1', '123456')).resolves.toBe(false);
    await expect(svc.consume('u1', '')).resolves.toBe(false);
  });
});

describe('a backup code works at the normal MFA step', () => {
  const PASSWORD = 'correct-horse-battery';

  async function harness() {
    const mem = memoryCodes();
    const recovery = new RecoveryCodesService(mem.prisma);
    const user: any = {
      id: 'u1',
      email: 'a@b.test',
      phone: '+966555000111',
      passwordHash: await bcrypt.hash(PASSWORD, 4),
      region: 'KSA',
      role: 'USER',
      mfaEnabled: false,
      mfaSecret: null,
    };
    const prisma: any = {
      ...mem.prisma,
      user: { findUnique: async () => user, update: async ({ data }: any) => Object.assign(user, data) },
      otpCode: { create: async () => ({}), findFirst: async () => null, count: async () => 0 },
      loginChallenge: { create: async () => ({}) },
    };
    // The realistic state for someone using a backup code: there is NO pending OTP, and
    // the real OtpService THROWS "no pending code" for that — which is why the auth
    // service must not let that exception escape before the recovery path is tried.
    const otp: any = {
      issue: async () => '123456',
      verify: async () => {
        throw new Error('No pending code for this destination.');
      },
    };
    const tokens: any = { issueTokenPair: jest.fn().mockResolvedValue({ accessToken: 'a', refreshToken: 'r', user: {} }) };
    const svc = new AuthService(
      prisma,
      otp,
      tokens,
      {} as any,
      new TotpService({ get: () => 'x'.repeat(48) } as any),
      recovery,
    );
    return { svc, recovery, tokens };
  }

  it('logs in when the primary factor cannot be reached AT ALL', async () => {
    const h = await harness();
    const { codes } = await h.recovery.regenerate('u1');
    // No pending OTP, no authenticator — exactly the lost-phone case.
    await expect(h.svc.verifyMfaAndLogin('u1', codes[0])).resolves.toBeDefined();
    expect(h.tokens.issueTokenPair).toHaveBeenCalled();
  });

  it('will not accept the same code twice', async () => {
    const h = await harness();
    const { codes } = await h.recovery.regenerate('u1');
    await h.svc.verifyMfaAndLogin('u1', codes[0]);
    await expect(h.svc.verifyMfaAndLogin('u1', codes[0])).rejects.toThrow(/Invalid or expired/);
  });

  it('still rejects a plain wrong code', async () => {
    const h = await harness();
    await h.recovery.regenerate('u1');
    await expect(h.svc.verifyMfaAndLogin('u1', 'ZZZZ-ZZZZ-ZZZZ')).rejects.toThrow(/Invalid or expired/);
  });
});
