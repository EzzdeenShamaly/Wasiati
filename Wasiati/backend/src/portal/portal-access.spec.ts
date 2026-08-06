import { ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PATH_METADATA } from '@nestjs/common/constants';
import { PortalService, PORTAL_NOT_RELEASED_MESSAGE } from './portal.service';
import { PortalController } from './portal.controller';
import { ClaimTokenContext } from '../death-claims/claim-token.guard';

/**
 * The portal hands a person with no account read access to a dead person's estate. Three
 * things have to hold, and each is driven below:
 *
 *   1. CONTENT IS UNREADABLE UNTIL RELEASE, and the refusal says the same thing for every
 *      status that is not RELEASED — otherwise the portal is a progress tracker for a claim
 *      someone else filed.
 *   2. A SESSION IS PINNED TO ONE ESTATE by the token, with no caller-supplied will id
 *      anywhere on the surface.
 *   3. THE SESSION TOKEN IS NOT A JWT, so it cannot be replayed at an account route.
 */

const ALL_STATUSES = ['SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'RELEASED'] as const;
const NOT_RELEASED = ALL_STATUSES.filter((s) => s !== 'RELEASED');

const WILLS: Record<string, any> = {
  'will-A': {
    id: 'will-A',
    ownerId: 'owner-A',
    personalMessage: 'Message that belongs to estate A',
    funeralWishes: { sunnah: true, azaa: 'A' },
    guardianMode: 'named',
    guardianName: 'Guardian A',
    guardianPhone: '+15550000001',
    guardianEmail: 'guardian-a@x.com',
    owner: { id: 'owner-A', email: 'a@x.com' },
  },
  'will-B': {
    id: 'will-B',
    ownerId: 'owner-B',
    personalMessage: 'Message that belongs to estate B',
    funeralWishes: null,
    guardianMode: null,
    owner: { id: 'owner-B', email: 'b@x.com' },
  },
};

const SHARES: Record<string, any[]> = {
  'will-A': [{ heirName: 'Heir A', heirRelation: 'SON', sharePercent: 50 }],
  'will-B': [{ heirName: 'Heir B', heirRelation: 'DAUGHTER', sharePercent: 25 }],
};

const ASSETS: Record<string, any[]> = {
  'will-A': [
    {
      type: 'BANK_ACCOUNT',
      label: 'Chase checking',
      institution: 'Chase',
      estimatedValue: 1000.5,
      currency: 'USD',
      notes: null,
      contactPhone: '+15551112222',
      contactEmail: 'branch@chase.example',
      accountRef: 'US00-1234-5678',
    },
  ],
  'will-B': [],
};

function makeService(opts: { status?: string; claim?: any } = {}) {
  const audited: any[] = [];
  const claim =
    opts.claim === null
      ? null
      : (opts.claim ?? { id: 'claim-1', status: opts.status ?? 'RELEASED', trusteeOverrideAt: null });

  const prisma: any = {
    will: { findUnique: async ({ where }: any) => WILLS[where.id] ?? null },
    deathClaim: { findUnique: async () => claim },
    shariaShare: { findMany: async ({ where }: any) => SHARES[where.willId] ?? [] },
    bequest: { findMany: async () => [] },
    asset: { findMany: async ({ where }: any) => ASSETS[where.willId] ?? [] },
    witness: { findMany: async () => [] },
    willHeirContact: { findMany: async () => [] },
    heirReleaseConfirmation: { findMany: async () => [], upsert: async (a: any) => ({ confirmedAt: new Date(), ...a }) },
    fileObject: {
      findMany: async ({ where }: any) =>
        where.userId === 'owner-A'
          ? [
              { id: 'file-A1', contentType: 'video/mp4', sizeBytes: 10, createdAt: new Date('2026-01-01'), userId: 'owner-A' },
              { id: 'file-A2', contentType: 'video/mp4', sizeBytes: 20, createdAt: new Date('2026-02-01'), userId: 'owner-A' },
            ]
          : [],
    },
    claimAccessToken: { findUnique: async () => ({ subjectEmail: 'heir@x.com', subjectPhone: '' }), updateMany: async () => ({ count: 1 }) },
    trustee: { findMany: async () => [] },
  };
  const otp: any = { issue: async () => '123456', verify: async () => true };
  const files: any = { presignDownloadForRelease: async (_o: string, id: string) => ({ url: `https://signed.example/${id}` }) };
  const audit: any = { log: async (e: any) => audited.push(e) };
  const config: any = { get: () => undefined };
  const documents: any = { renderPdf: async () => Buffer.from('%PDF-1.7 test') };
  return { svc: new PortalService(prisma, otp, files, audit, config, documents, { incrWithTtl: async () => 1 } as any), audited };
}

const ctxFor = (willId: string, over: Partial<ClaimTokenContext> = {}): ClaimTokenContext => ({
  tokenId: 'tok-1',
  willId,
  claimId: 'claim-1',
  role: 'HEIR' as any,
  scope: 'PORTAL_READ' as any,
  heirContactId: 'heir-1',
  ...over,
});

describe('portal content is unreadable until the will is RELEASED', () => {
  // Table-driven over EVERY status × EVERY content endpoint. A new content endpoint that
  // forgets assertReleased fails here the moment it is added to this list.
  const CONTENT_ENDPOINTS: [string, (svc: PortalService, ctx: ClaimTokenContext) => Promise<unknown>][] = [
    ['GET /portal/will', (svc, ctx) => svc.will(ctx, {})],
    ['GET /portal/will/videos', (svc, ctx) => svc.videos(ctx, {})],
    ['GET /portal/will/pdf', (svc, ctx) => svc.pdf(ctx, {})],
  ];

  for (const [name, call] of CONTENT_ENDPOINTS) {
    for (const status of NOT_RELEASED) {
      it(`${name} REFUSES a ${status} claim`, async () => {
        const { svc } = makeService({ status });
        await expect(call(svc, ctxFor('will-A'))).rejects.toBeInstanceOf(ForbiddenException);
      });
    }

    it(`${name} serves a RELEASED claim`, async () => {
      const { svc } = makeService({ status: 'RELEASED' });
      await expect(call(svc, ctxFor('will-A'))).resolves.toBeDefined();
    });

    // A claim row that has vanished must not read as "released".
    it(`${name} REFUSES when the claim is gone`, async () => {
      const { svc } = makeService({ claim: null });
      await expect(call(svc, ctxFor('will-A'))).rejects.toBeInstanceOf(ForbiddenException);
    });
  }

  /**
   * THE POINT OF THE WHOLE GATE. If SUBMITTED, UNDER_REVIEW, APPROVED and REJECTED were
   * distinguishable through a content endpoint, anyone holding an heir's session could poll
   * /portal/will and watch a claim advance — including learning that a claim they were
   * never told about had been approved. One constant body for all four.
   */
  it('returns a byte-identical 403 body for ALL FOUR non-released statuses', async () => {
    const bodies: unknown[] = [];
    for (const status of NOT_RELEASED) {
      const { svc } = makeService({ status });
      for (const [, call] of CONTENT_ENDPOINTS) {
        try {
          await call(svc, ctxFor('will-A'));
          throw new Error(`expected a refusal for ${status}`);
        } catch (e) {
          expect(e).toBeInstanceOf(ForbiddenException);
          bodies.push((e as ForbiddenException).getResponse());
        }
      }
    }
    expect(bodies).toHaveLength(NOT_RELEASED.length * CONTENT_ENDPOINTS.length);
    for (const body of bodies) expect(body).toEqual(bodies[0]);
    expect(JSON.stringify(bodies[0])).toContain(PORTAL_NOT_RELEASED_MESSAGE);
  });

  // Status IS available — deliberately, in exactly one place, which is the screen the
  // prototype designs for it ("Claim under review"). The gate is on CONTENT, not on the
  // existence of the claim.
  it('still reports status on /portal/claim and /portal/me while unreleased', async () => {
    const { svc } = makeService({ status: 'UNDER_REVIEW' });
    await expect(svc.claim(ctxFor('will-A'))).resolves.toEqual({ status: 'UNDER_REVIEW' });
    await expect(svc.me(ctxFor('will-A'))).resolves.toMatchObject({ claimStatus: 'UNDER_REVIEW', readOnly: true });
  });
});

describe('the RELEASED estate is served WHOLE', () => {
  /**
   * The purge job erases everything at day 90, so anything this payload omits is
   * destroyed unread. It used to carry only the message, shares and bequests — the asset
   * inventory, funeral wishes and guardianship died with the clock, and only the single
   * most-recent video was served. The vault alone is excluded, by design (DECISIONS §19).
   */
  it('GET /portal/will carries assets (unmasked accountRef), funeral wishes and guardianship', async () => {
    const { svc } = makeService({ status: 'RELEASED' });
    const a = (await svc.will(ctxFor('will-A'), {})) as any;

    expect(a.assets).toEqual([
      expect.objectContaining({
        type: 'BANK_ACCOUNT',
        label: 'Chase checking',
        institution: 'Chase',
        estimatedValue: 1000.5, // number, never a Prisma Decimal's string form
        currency: 'USD',
        contactPhone: '+15551112222',
        contactEmail: 'branch@chase.example',
        // UNMASKED: this payload exists so the heirs can locate the asset.
        accountRef: 'US00-1234-5678',
      }),
    ]);
    expect(a.funeralWishes).toEqual({ sunnah: true, azaa: 'A' });
    expect(a.guardianship).toEqual({
      mode: 'named',
      name: 'Guardian A',
      phone: '+15550000001',
      email: 'guardian-a@x.com',
    });
    // An estate that recorded neither is explicit about it, not absent.
    const b = (await svc.will(ctxFor('will-B'), {})) as any;
    expect(b.funeralWishes).toBeNull();
    expect(b.guardianship).toBeNull();
    expect(b.assets).toEqual([]);
  });

  it('GET /portal/will/videos serves ALL videos oldest-first, each with its own URL', async () => {
    const { svc } = makeService({ status: 'RELEASED' });
    const res = (await svc.videos(ctxFor('will-A'), {})) as any;
    expect(res.videos.map((v: any) => v.fileId)).toEqual(['file-A1', 'file-A2']);
    expect(res.videos.map((v: any) => v.url)).toEqual([
      'https://signed.example/file-A1',
      'https://signed.example/file-A2',
    ]);
    // No videos is an empty list, not an error — the caller is already past the gate.
    const none = (await svc.videos(ctxFor('will-B'), {})) as any;
    expect(none.videos).toEqual([]);
  });

  it('GET /portal/will/pdf renders through WillDocumentService and returns the bytes', async () => {
    const { svc } = makeService({ status: 'RELEASED' });
    const pdf = await svc.pdf(ctxFor('will-A'), {});
    expect(Buffer.isBuffer(pdf)).toBe(true);
    expect(pdf.toString()).toContain('%PDF');
  });
});

describe('a portal session is pinned to the estate in its token', () => {
  it('a token for will A reads A, and there is no argument by which it could read B', async () => {
    const { svc } = makeService({ status: 'RELEASED' });
    const a = (await svc.will(ctxFor('will-A'), {})) as any;
    expect(a.personalMessage).toBe('Message that belongs to estate A');
    expect(a.shariaShares[0].heirName).toBe('Heir A');

    // Same service, same call shape — only the TOKEN differs, and that is the only thing
    // that can differ, because willId is not a parameter of any portal route.
    const b = (await svc.will(ctxFor('will-B'), {})) as any;
    expect(b.personalMessage).toBe('Message that belongs to estate B');
    expect(JSON.stringify(b)).not.toContain('estate A');
  });

  /**
   * The structural half of the same claim: NO portal route may take a will identifier in
   * its path. This is what makes the scoping impossible to forget on a future endpoint —
   * there is no `:willId` for a new route to copy and then fail to authorise.
   */
  it('declares no path parameter on any route', () => {
    const methods = Object.getOwnPropertyNames(PortalController.prototype).filter((m) => m !== 'constructor');
    expect(methods.length).toBeGreaterThan(0);
    for (const m of methods) {
      const path = Reflect.getMetadata(PATH_METADATA, (PortalController.prototype as any)[m]);
      expect(String(path ?? '')).not.toContain(':');
    }
  });
});

describe('the portal session token is NOT a JWT', () => {
  const SESSION_SECRET = 'test-session-secret';

  async function mintPortalToken(): Promise<string> {
    const created: any[] = [];
    const prisma: any = {
      deathClaim: {
        // resolveParty now ranks candidates from findMany (status priority, then recency).
        findMany: async () => [
          {
            id: 'claim-1',
            status: 'RELEASED',
            willId: 'will-A',
            will: {
              owner: { email: 'owner@x.com' },
              heirContacts: [{ id: 'heir-1', phone: null, email: 'heir@x.com' }],
              trustees: [],
            },
          },
        ],
      },
      claimAccessToken: { create: async (a: any) => created.push(a.data) },
    };
    const otp: any = { verify: async () => true };
    const svc = new PortalService(
      prisma,
      otp,
      {} as any,
      { log: async () => undefined } as any,
      { get: () => undefined } as any,
      {} as any,
      { incrWithTtl: async () => 1 } as any,
    );
    const { token } = await svc.verify('HEIR' as any, 'heir@x.com', '123456');
    // Only the hash is persisted — the raw value never touches a column.
    expect(created[0].tokenHash).toHaveLength(64);
    expect(created[0].tokenHash).not.toBe(token);
    return token;
  }

  /**
   * WHY THIS TEST EXISTS. JwtStrategy (auth/strategies/jwt.strategy.ts) accepts ANY HS256
   * token signed with SESSION_SECRET and maps `sub` straight to a userId — there is no
   * token-type discrimination. So a portal credential issued as a JWT under the same secret
   * would authenticate at EVERY JwtAuthGuard route in the product: an heir reading a will
   * would hold a full account session. The defence is that a portal token is not a JWT at
   * all — it is 256 bits of opaque random, and the server keeps only its SHA-256.
   *
   * The verification below is the exact one JwtStrategy performs (HS256, secretOrKey =
   * SESSION_SECRET), with a real JWT as a positive control so a broken harness cannot make
   * this pass by accident.
   */
  it('fails the same verification JwtStrategy performs', async () => {
    const token = await mintPortalToken();
    const jwt = new JwtService({});

    // Positive control: the check is live and does accept a genuine token.
    const realJwt = jwt.sign({ sub: 'user-1' }, { secret: SESSION_SECRET, algorithm: 'HS256' });
    expect(jwt.verify(realJwt, { secret: SESSION_SECRET, algorithms: ['HS256'] })).toMatchObject({ sub: 'user-1' });

    expect(() => jwt.verify(token, { secret: SESSION_SECRET, algorithms: ['HS256'] })).toThrow();
  });

  it('is opaque: 43 base64url characters, with no JWT structure to parse', async () => {
    const token = await mintPortalToken();
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(token).not.toContain('.'); // a JWT is header.payload.signature
  });
});
