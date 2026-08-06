import { UnauthorizedException } from '@nestjs/common';
import { TokenService } from './token.service';

/**
 * A session that has sat idle must require signing in again.
 *
 * The refresh token lives 30 days, so before this a tab left open overnight — or a
 * browser reopened days later — silently refreshed straight back onto the dashboard.
 * The owner's requirement (24 Jul 2026): an hour of no activity means sign in again.
 *
 * The clock is the AGE OF THE PRESENTED TOKEN, which works because every refresh
 * rotates: the row the client holds was minted at its last refresh, so its age is the
 * time since this session last did anything. No extra column, and nothing the client
 * can lie about. Note the two timers are independent — `expiresAt` remains the
 * absolute ceiling, this is the idle one.
 */
function makeService(row: any, idleMinutes: string | undefined = '60') {
  const state = { familyRevoked: false, revoked: false, created: 0 };
  const prisma: any = {
    refreshToken: {
      findUnique: async () => row,
      updateMany: async ({ where, data }: any) => {
        if (where.familyId) {
          state.familyRevoked = true;
          return { count: 1 };
        }
        if (where.revokedAt === null && !state.revoked) {
          state.revoked = true;
          Object.assign(row, data);
          return { count: 1 };
        }
        return { count: 0 };
      },
      create: async () => {
        state.created += 1;
        return { id: `new${state.created}` };
      },
      update: async () => row,
    },
    $transaction: async (fn: any) => fn(prisma),
  };
  const config: any = {
    get: (k: string) =>
      k === 'REFRESH_TOKEN_TTL_DAYS' ? '30'
      : k === 'ACCESS_TOKEN_TTL' ? '15m'
      : k === 'SESSION_IDLE_TIMEOUT_MINUTES' ? idleMinutes
      : undefined,
  };
  const jwt: any = { sign: () => 'access-token' };
  return { svc: new TokenService(prisma, jwt, config), state };
}

/** A live token last refreshed `ageMs` ago. */
const rowAged = (ageMs: number): any => ({
  id: 't1',
  userId: 'u1',
  familyId: 'f1',
  tokenHash: 'h',
  revokedAt: null,
  replacedById: null,
  expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // absolute ceiling, far away
  createdAt: new Date(Date.now() - ageMs),
  user: { id: 'u1', email: 'a@b.com', region: 'US', role: 'USER' },
});

const MIN = 60_000;

describe('session idle timeout', () => {
  it('refuses a session idle for more than an hour', async () => {
    const { svc } = makeService(rowAged(61 * MIN));
    await expect(svc.rotateRefreshToken('raw')).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('says WHY, so the app can show "please sign in" rather than a generic failure', async () => {
    const { svc } = makeService(rowAged(90 * MIN));
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/timed out/i);
  });

  it('revokes the family, so the stale cookie in a forgotten tab is spent for good', async () => {
    const { svc, state } = makeService(rowAged(120 * MIN));
    await expect(svc.rotateRefreshToken('raw')).rejects.toBeInstanceOf(UnauthorizedException);
    expect(state.familyRevoked).toBe(true);
  });

  it('lets an ACTIVE session through — 14 minutes idle is just a normal refresh', async () => {
    const { svc } = makeService(rowAged(14 * MIN));
    const res = await svc.rotateRefreshToken('raw');
    expect(res.accessToken).toBe('access-token');
    expect(res.user.id).toBe('u1');
  });

  it('still allows a session just under the hour', async () => {
    const { svc } = makeService(rowAged(59 * MIN));
    await expect(svc.rotateRefreshToken('raw')).resolves.toMatchObject({ accessToken: 'access-token' });
  });

  it('is configurable — a 15-minute policy rejects a 20-minute idle', async () => {
    const { svc } = makeService(rowAged(20 * MIN), '15');
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/timed out/i);
  });

  it('can be disabled with 0, restoring the old always-on behaviour', async () => {
    const { svc } = makeService(rowAged(30 * 24 * 60 * MIN), '0');
    await expect(svc.rotateRefreshToken('raw')).resolves.toMatchObject({ accessToken: 'access-token' });
  });

  it('defaults to an hour when the env var is absent', async () => {
    const { svc } = makeService(rowAged(61 * MIN), undefined);
    expect(svc.sessionIdleTimeoutMs).toBe(60 * MIN);
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/timed out/i);
  });

  it('reports reuse, not idleness, when a revoked token is replayed after an hour', async () => {
    // Both conditions hold; the stolen-token signal is the one that must surface.
    const stale = rowAged(120 * MIN);
    stale.revokedAt = new Date();
    const { svc } = makeService(stale);
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/reuse/i);
  });
});
