import { VaultService } from './vault.service';

/**
 * The vault KDF salt must be: random, unique per user, and STABLE once set (changing
 * it would orphan every already-encrypted item). These pin that.
 */
function makeService(
  seed: { userId: string; kdfSalt: string | null; kekVerifier?: string | null } | null,
  opts: { itemCount?: number } = {},
) {
  let row: any = seed ? { kekVerifier: null, ...seed } : seed;
  const prisma: any = {
    vault: {
      upsert: async ({ where, create }: any) => {
        if (!row) row = { userId: where.userId, id: 'v1', kdfSalt: create.kdfSalt, kekVerifier: null };
        return { id: 'v1', ...row };
      },
      // Honours BOTH conditional writes rather than assuming which one is being made. The
      // verifier's write-once guard lives in its WHERE, so a double that ignored it would
      // pass with the guard deleted — and a deleted guard means a typo can overwrite the
      // verifier and lock the real passphrase out of the vault permanently.
      updateMany: async ({ where, data }: any) => {
        if (!row) return { count: 0 };
        if ('kekVerifier' in (where ?? {})) {
          if (row.kekVerifier !== null) return { count: 0 };
          row.kekVerifier = data.kekVerifier;
          return { count: 1 };
        }
        if (row.kdfSalt === null) {
          row.kdfSalt = data.kdfSalt;
          return { count: 1 };
        }
        return { count: 0 };
      },
      findUnique: async () => (row ? { kdfSalt: row.kdfSalt, kekVerifier: row.kekVerifier } : null),
    },
    vaultItem: { count: async () => opts.itemCount ?? 0 },
  };
  const entitlements = { resolve: jest.fn().mockResolvedValue({ tier: 'STANDARD' }) } as any;
  return { svc: new VaultService(prisma, entitlements), getRow: () => row };
}

describe('VaultService.getKdfSalt', () => {
  it('generates a random base64 salt for a new vault', async () => {
    const { svc } = makeService(null);
    const { salt } = await svc.getKdfSalt('u1');
    expect(salt).toMatch(/^[A-Za-z0-9+/]+=*$/);
    expect(Buffer.from(salt, 'base64').length).toBe(16); // 128-bit
  });

  it('returns the SAME salt on repeated calls (stable — never re-rolled)', async () => {
    const { svc } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=' });
    const a = await svc.getKdfSalt('u1');
    const b = await svc.getKdfSalt('u1');
    expect(a.salt).toBe('Zml4ZWQtc2FsdC0xNmI=');
    expect(b.salt).toBe(a.salt);
  });

  it('backfills a salt-less existing vault exactly once', async () => {
    const { svc, getRow } = makeService({ userId: 'u1', kdfSalt: null });
    const { salt } = await svc.getKdfSalt('u1');
    expect(salt).toBeTruthy();
    expect(getRow()!.kdfSalt).toBe(salt); // persisted
  });

  it('different users get different salts', async () => {
    const a = await makeService(null).svc.getKdfSalt('u1');
    const b = await makeService(null).svc.getKdfSalt('u2');
    expect(a.salt).not.toBe(b.salt);
  });
});

/**
 * The passphrase verifier — the thing that stops a typo destroying a vault.
 *
 * Unlock used to check the passphrase's LENGTH and nothing else, so a mistyped passphrase
 * derived a different KEK, unlocked anyway (labels are plaintext, so the list looked right),
 * and every secret written afterwards was encrypted under a key nobody would ever hold
 * again. There is no recovery — DECISIONS §19.
 *
 * The server cannot check the blob; it has no passphrase and no KEK, by design. Its only
 * job is to store the FIRST one and never let it be replaced.
 */
describe('VaultService.setKekVerifier — write-once', () => {
  const BLOB = 'bm9uY2U='.repeat(4); // shape only; the server never interprets it

  it('stores the first verifier a vault is given', async () => {
    const { svc, getRow } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=' });
    await expect(svc.setKekVerifier('u1', BLOB)).resolves.toEqual({ stored: true });
    expect(getRow()!.kekVerifier).toBe(BLOB);
  });

  // THE ONE THAT MATTERS. If a second write could replace it, a typo would not merely fail
  // to unlock — it would overwrite the verifier and lock the REAL passphrase out, turning a
  // recoverable mistake into exactly the permanent loss this column exists to prevent.
  it('REFUSES to replace an existing verifier, and does not error doing so', async () => {
    const { svc, getRow } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=', kekVerifier: BLOB });
    await expect(svc.setKekVerifier('u1', 'ZGlmZmVyZW50'.repeat(3))).resolves.toEqual({ stored: false });
    expect(getRow()!.kekVerifier).toBe(BLOB); // untouched
  });

  it('rejects a blob of implausible shape rather than writing it into a write-once column', async () => {
    const { svc } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=' });
    await expect(svc.setKekVerifier('u1', 'short')).rejects.toThrow(/Invalid vault verifier/);
    await expect(svc.setKekVerifier('u1', 'x'.repeat(513))).rejects.toThrow(/Invalid vault verifier/);
  });
});

describe('VaultService.getKdfSalt — what unlock needs to judge a passphrase', () => {
  it('reports the verifier and whether the vault holds anything', async () => {
    const { svc } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=', kekVerifier: 'abc' }, { itemCount: 3 });
    await expect(svc.getKdfSalt('u1')).resolves.toEqual({
      salt: 'Zml4ZWQtc2FsdC0xNmI=',
      verifier: 'abc',
      hasItems: true,
    });
  });

  // hasItems is what tells the client whether a verifier-less vault can be PROVEN against
  // real ciphertext or is simply new. Reporting it wrongly would either block a legitimate
  // unlock or let an unprovable one through.
  it('reports an empty vault as empty', async () => {
    const { svc } = makeService({ userId: 'u1', kdfSalt: 'Zml4ZWQtc2FsdC0xNmI=' }, { itemCount: 0 });
    const res = await svc.getKdfSalt('u1');
    expect(res.hasItems).toBe(false);
    expect(res.verifier).toBeNull();
  });
});
