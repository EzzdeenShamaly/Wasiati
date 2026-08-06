import { UnauthorizedException } from '@nestjs/common';
import { TokenService } from './token.service';

/**
 * Refresh-token rotation must be atomic: two concurrent refreshes of the SAME token
 * must not both succeed. The winner rotates; the loser is treated as reuse and the
 * family is revoked. Modelled with a claim counter that mimics the conditional
 * updateMany (revokedAt: null) the fix relies on.
 */
function makeService(tokenRow: any) {
  const state = { revoked: false, familyRevoked: false, created: 0 };

  const prisma: any = {
    refreshToken: {
      findUnique: async () => tokenRow,
      updateMany: async ({ where, data }: any) => {
        // revokeFamily path
        if (where.familyId) {
          state.familyRevoked = true;
          return { count: 1 };
        }
        // atomic claim: only succeeds while not yet revoked
        if (where.revokedAt === null && !state.revoked) {
          state.revoked = true;
          Object.assign(tokenRow, data);
          return { count: 1 };
        }
        return { count: 0 };
      },
      create: async () => {
        state.created += 1;
        return { id: `new${state.created}` };
      },
      update: async () => tokenRow,
    },
    $transaction: async (fn: any) => fn(prisma),
  };

  const config: any = { get: (k: string) => (k === 'REFRESH_TOKEN_TTL_DAYS' ? '30' : k === 'ACCESS_TOKEN_TTL' ? '15m' : undefined) };
  const jwt: any = { sign: () => 'access-token' };
  return { svc: new TokenService(prisma, jwt, config), state };
}

const validRow = (): any => ({
  id: 't1',
  userId: 'u1',
  familyId: 'f1',
  tokenHash: 'h',
  revokedAt: null,
  replacedById: null,
  expiresAt: new Date(Date.now() + 60_000),
  // Freshly issued. The idle-timeout check reads this, and a real row always has it
  // (`@default(now())`); see session-idle-timeout.spec for that behaviour.
  createdAt: new Date(),
  user: { id: 'u1', email: 'a@b.com', region: 'US', role: 'USER' },
});

describe('TokenService.rotateRefreshToken', () => {
  it('rotates a valid token and returns a fresh pair', async () => {
    const { svc, state } = makeService(validRow());
    const res = await svc.rotateRefreshToken('raw');
    expect(res.accessToken).toBe('access-token');
    expect(res.refreshToken).toBeTruthy();
    expect(state.created).toBe(1);
  });

  it('a second rotation of an ALREADY-revoked token is reuse → family revoked', async () => {
    const row = validRow();
    row.revokedAt = new Date(); // already rotated
    const { svc, state } = makeService(row);
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(UnauthorizedException);
    expect(state.familyRevoked).toBe(true);
    expect(state.created).toBe(0);
  });

  it('the atomic claim means a lost race is treated as reuse, not a second live token', async () => {
    // The row still reads as valid (stale read), but another concurrent writer has
    // already won the claim — so the conditional updateMany returns count 0.
    const { svc, state } = makeService(validRow());
    state.revoked = true; // another writer already flipped revokedAt
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/reuse detected/i);
    expect(state.familyRevoked).toBe(true);
    expect(state.created).toBe(0); // no second live token minted
  });

  it('rejects an unknown token', async () => {
    const { svc } = makeService(null);
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects an expired token', async () => {
    const row = validRow();
    row.expiresAt = new Date(Date.now() - 1000);
    const { svc } = makeService(row);
    await expect(svc.rotateRefreshToken('raw')).rejects.toThrow(/expired/i);
  });
});
