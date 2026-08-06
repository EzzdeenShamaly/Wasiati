import { DeathClaimsService } from './death-claims.service';
import { DeathClaimsController } from './death-claims.controller';

/**
 * POST /death-claims/lookup is THE way in: a grieving family has no account, no willId
 * and no link — only the deceased's contact details and their own. It is public and
 * unauthenticated, which makes its response the most attackable surface in the product.
 *
 * The invariant: the response is NOT a channel. Body and status are byte-identical for
 * every input — no such person, a person with no sealed will, a person found but the
 * caller is not on their will, and a full match. Only the last case mints anything, and
 * the link goes to the contact ALREADY ON FILE, never to what was typed in the form.
 *
 * This REPLACES death-request-no-echo.spec.ts, which pinned the same "identical body"
 * property on `startDeathRequest` — a method deleted with its route. The assertions here
 * are strictly stronger: that test compared two bodies, this one compares body AND status
 * across all four cases and checks that the mint happened in exactly one of them.
 */

const DECEASED_EMAIL = 'deceased@x.com';
const WITNESS_PHONE = '+966555000111';

type Case = 'no-such-person' | 'no-sealed-will' | 'not-a-party' | 'match';

function makeService(kase: Case) {
  const minted: any[] = [];
  const sms: { to: string; body: string }[] = [];
  const emails: { to: string; body: string }[] = [];

  const willRow = {
    id: 'will-1',
    witnesses: [{ id: 'w1', phone: WITNESS_PHONE, email: 'witness@x.com' }],
    trustees: [],
    heirContacts: [],
    owner: { claimInitPolicy: 'BOTH' },
  };

  const prisma: any = {
    user: {
      findFirst: async () => (kase === 'no-such-person' ? null : { id: 'user-1' }),
      findMany: async () => (kase === 'no-such-person' ? [] : [{ id: 'user-1', phone: '+966555999999' }]),
    },
    will: {
      findMany: async () => (kase === 'no-sealed-will' ? [] : [willRow]),
    },
    claimAccessToken: {
      // The dummy-work probe on the miss path.
      findUnique: async () => null,
      create: async ({ data }: any) => {
        minted.push(data);
        return { id: 'tok-1', ...data };
      },
    },
  };

  const notifications: any = {
    sendSms: async (to: string, body: string) => {
      sms.push({ to, body });
    },
    sendEmail: async (to: string, _subject: string, body: string) => {
      emails.push({ to, body });
    },
  };
  const config: any = { get: (k: string) => (k === 'APP_BASE_URL' ? 'https://app.wasiati.com' : undefined) };
  const redis: any = { incrWithTtl: async () => 1 };

  const svc = new DeathClaimsService(prisma, notifications, {} as any, {} as any, config, redis, {} as any);
  return { svc, minted, sms, emails };
}

/** The claimant contact each case should be probed with. */
const claimantFor = (kase: Case) => (kase === 'not-a-party' ? '+15550009999' : WITNESS_PHONE);

const run = (kase: Case) => {
  const h = makeService(kase);
  return h.svc.lookup(DECEASED_EMAIL, claimantFor(kase)).then((res) => ({ ...h, res }));
};

/** Lets the fire-and-forget delivery settle before assertions. */
const flush = () => new Promise((r) => setImmediate(r));

const ALL_CASES: Case[] = ['no-such-person', 'no-sealed-will', 'not-a-party', 'match'];

describe('POST /death-claims/lookup — constant response', () => {
  it('returns the identical body in every case', async () => {
    const bodies = [];
    for (const kase of ALL_CASES) bodies.push((await run(kase)).res);

    for (const b of bodies) expect(b).toEqual({ acknowledged: true });
    // Serialised comparison, so an extra key or a differently-ordered one is caught —
    // `toEqual` alone would pass a body that carries a stray field on one path.
    const serialised = bodies.map((b) => JSON.stringify(b));
    expect(new Set(serialised).size).toBe(1);
  });

  // The status code is as much of an oracle as the body: a 404 for an unknown person
  // and a 202 for a known one tells an attacker everything the body refuses to.
  it('is declared 202 on the route, unconditionally', () => {
    // The handler has no way to vary the status — it returns a plain object and the
    // @HttpCode(ACCEPTED) decorator fixes the code for every outcome. Pin the decorator.
    const code = Reflect.getMetadata('__httpCode__', DeathClaimsController.prototype.lookup);
    expect(code).toBe(202);
  });

  it('never throws, whatever the database does', async () => {
    const prisma: any = {
      user: {
        findFirst: async () => {
          throw new Error('database on fire');
        },
      },
    };
    const svc = new DeathClaimsService(
      prisma,
      {} as any,
      {} as any,
      {} as any,
      { get: () => undefined } as any,
      { incrWithTtl: async () => 1 } as any,
      {} as any,
    );
    // An escaping exception is a 500, and a 500 on one input next to a 202 on another is
    // exactly the oracle the constant body exists to close.
    await expect(svc.lookup(DECEASED_EMAIL, WITNESS_PHONE)).resolves.toEqual({ acknowledged: true });
  });
});

describe('POST /death-claims/lookup — an invite is minted ONLY on a full match', () => {
  for (const kase of ['no-such-person', 'no-sealed-will', 'not-a-party'] as Case[]) {
    it(`mints nothing and sends nothing for: ${kase}`, async () => {
      const { minted, sms, emails } = await run(kase);
      await flush();
      expect(minted).toHaveLength(0);
      expect(sms).toHaveLength(0);
      expect(emails).toHaveLength(0);
    });
  }

  it('mints exactly one CLAIM_SUBMIT token when both sides match', async () => {
    const { minted } = await run('match');
    expect(minted).toHaveLength(1);
    expect(minted[0]).toMatchObject({
      willId: 'will-1',
      scope: 'CLAIM_SUBMIT',
      role: 'WITNESS',
    });
  });

  it('stores only a HASH of the token, never the token itself', async () => {
    const { minted } = await run('match');
    const row = minted[0];
    expect(row.tokenHash).toMatch(/^[0-9a-f]{64}$/); // sha-256 hex
    expect(row).not.toHaveProperty('token');
    // Whatever went out in the link must not be sitting in the row.
    const { sms } = await run('match');
    await flush();
    const sent = sms[0]?.body.match(/\/claim\/([A-Za-z0-9_-]+)/)?.[1];
    if (sent) expect(row.tokenHash).not.toBe(sent);
  });

  it('mints a token that expires', async () => {
    const { minted } = await run('match');
    expect(minted[0].expiresAt).toBeInstanceOf(Date);
    expect(minted[0].expiresAt.getTime()).toBeGreaterThan(Date.now());
  });
});

describe('POST /death-claims/lookup — delivery goes to the contact ON FILE', () => {
  /**
   * The attack this closes: a stranger who learns the deceased's email and a witness's
   * phone types their OWN number into `claimantContact` and receives the claim link.
   * Matching on the typed value but DELIVERING to the stored one means knowing a contact
   * gets you nothing you did not already have.
   */
  it('sends the link to the stored phone, not to the one that was typed', async () => {
    const h = makeService('match');
    // Same line, spelled the way a person types it — matches the roster, but is not the
    // string on file.
    await h.svc.lookup(DECEASED_EMAIL, '0555000111');
    await flush();

    expect(h.minted).toHaveLength(1);
    expect(h.sms).toHaveLength(1);
    expect(h.sms[0].to).toBe(WITNESS_PHONE); // the roster's value
    expect(h.sms[0].body).toContain('https://app.wasiati.com/claim/');
  });

  it('binds the token to the roster contact, not the submitted one', async () => {
    const h = makeService('match');
    await h.svc.lookup(DECEASED_EMAIL, '0555000111');
    expect(h.minted[0].subjectPhone).toBe(WITNESS_PHONE);
  });

  // The message must not confirm who died or that a will exists for a named person —
  // it is delivered to a phone we believe is the party's, but delivery is not proof.
  it('does not name the deceased in the outgoing message', async () => {
    const h = makeService('match');
    await h.svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    await flush();
    expect(h.sms[0].body).not.toContain(DECEASED_EMAIL);
  });
});

describe('POST /death-claims/lookup — abuse counters', () => {
  function limitedService(counts: number[]) {
    const minted: any[] = [];
    let i = 0;
    const prisma: any = {
      user: { findFirst: async () => ({ id: 'user-1' }), findMany: async () => [] },
      will: {
        findMany: async () => [
          {
            id: 'will-1',
            witnesses: [{ id: 'w1', phone: WITNESS_PHONE, email: null }],
            trustees: [],
            heirContacts: [],
            owner: { claimInitPolicy: 'BOTH' },
          },
        ],
      },
      claimAccessToken: {
        findUnique: async () => null,
        create: async ({ data }: any) => {
          minted.push(data);
          return { id: 't', ...data };
        },
      },
    };
    const redis: any = { incrWithTtl: async () => counts[i++] ?? 1 };
    const svc = new DeathClaimsService(
      prisma,
      { sendSms: async () => undefined, sendEmail: async () => undefined } as any,
      {} as any,
      {} as any,
      { get: () => undefined } as any,
      redis,
      {} as any,
    );
    return { svc, minted };
  }

  it('mints while under the per-will limit', async () => {
    const { svc, minted } = limitedService([1, 1, 1]);
    await svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    expect(minted).toHaveLength(1);
  });

  it('mints NOTHING once the per-will limit (3/24h) is exceeded', async () => {
    const { svc, minted } = limitedService([4]); // 4th invite for this will today
    await svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    expect(minted).toHaveLength(0);
  });

  it('mints NOTHING once the per-destination hourly limit (3/h) is exceeded', async () => {
    const { svc, minted } = limitedService([1, 4]);
    await svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    expect(minted).toHaveLength(0);
  });

  it('mints NOTHING once the per-destination daily limit (10/day) is exceeded', async () => {
    const { svc, minted } = limitedService([1, 1, 11]);
    await svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    expect(minted).toHaveLength(0);
  });

  // These counters are the ONLY abuse control an IP-rotating attacker cannot shed, so
  // losing them must stop the sending, not wave it through.
  it('FAILS CLOSED when Redis is unreachable', async () => {
    const { svc, minted } = limitedService([]);
    (svc as any).redis = {
      incrWithTtl: async () => {
        throw new Error('ECONNREFUSED');
      },
    };
    await svc.lookup(DECEASED_EMAIL, WITNESS_PHONE);
    expect(minted).toHaveLength(0);
  });

  // Even when it refuses to send, the response must not change.
  it('still returns the identical body when a limit blocks the send', async () => {
    const { svc } = limitedService([4]);
    await expect(svc.lookup(DECEASED_EMAIL, WITNESS_PHONE)).resolves.toEqual({ acknowledged: true });
  });
});
