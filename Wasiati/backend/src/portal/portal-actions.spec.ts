import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PortalService } from './portal.service';
import { ClaimTokenContext } from '../death-claims/claim-token.guard';

/**
 * The two write actions the portal exposes, and the audit trail behind every read.
 *
 * Both writes decide whether a will is released, so each is pinned to ONE role and recorded.
 * The prototype is explicit on both counts: "Confirmation recorded · logged to the audit
 * trail", "Trustee override recorded · logged to the audit trail", and "Document access is
 * logged to the audit trail".
 */

function makeService(opts: { status?: string; overrideAt?: Date | null; trustees?: any[]; subject?: any } = {}) {
  const audited: any[] = [];
  const upserts: any[] = [];
  const claimUpdates: any[] = [];
  const tokenUpdates: any[] = [];
  const trusteeUpdates: any[] = [];
  const roster: any[] = opts.trustees ?? [
    { id: 'trustee-1', phone: '+966555000111', email: 'trustee@x.com', status: 'CONFIRMED' },
  ];
  const claim = {
    id: 'claim-1',
    status: opts.status ?? 'APPROVED',
    trusteeOverrideAt: opts.overrideAt ?? null,
    trusteeOverrideBy: null as string | null,
  };

  const prisma: any = {
    will: {
      findUnique: async () => ({
        id: 'will-1',
        ownerId: 'owner-1',
        personalMessage: 'For my children',
        owner: { id: 'owner-1', email: 'owner@x.com' },
      }),
    },
    deathClaim: {
      findUnique: async () => claim,
      updateMany: async ({ where, data }: any) => {
        if (where.status && where.status !== claim.status) return { count: 0 };
        if (where.trusteeOverrideAt === null && claim.trusteeOverrideAt !== null) return { count: 0 };
        Object.assign(claim, data);
        claimUpdates.push(data);
        return { count: 1 };
      },
    },
    heirReleaseConfirmation: {
      findMany: async () => [],
      upsert: async (args: any) => {
        upserts.push(args);
        return { confirmedAt: new Date('2026-07-19T00:00:00Z') };
      },
    },
    willHeirContact: { findMany: async () => [] },
    shariaShare: { findMany: async () => [] },
    bequest: { findMany: async () => [] },
    asset: { findMany: async () => [] },
    witness: { findMany: async () => [] },
    fileObject: {
      findMany: async () => [
        {
          id: 'file-1',
          userId: 'owner-1',
          contentType: 'video/mp4',
          sizeBytes: 1024,
          createdAt: new Date('2026-05-03'),
        },
      ],
    },
    trustee: {
      // `status` is part of the fixture now. It was absent, and its absence was invisible:
      // override() never read it, so a roster row that had never accepted the role looked
      // exactly like one that had.
      findMany: async () => roster,
      // Honours `where.status`, so accepting twice cannot rewrite the first acceptance.
      updateMany: async ({ where, data }: any) => {
        const row = roster.find((t: any) => t.id === where.id);
        if (!row || (where.status && row.status !== where.status)) return { count: 0 };
        Object.assign(row, data);
        trusteeUpdates.push(data);
        return { count: 1 };
      },
    },
    claimAccessToken: {
      findUnique: async () => opts.subject ?? { subjectEmail: 'trustee@x.com', subjectPhone: '+966555000111' },
      updateMany: async ({ data }: any) => {
        tokenUpdates.push(data);
        return { count: 1 };
      },
    },
  };
  const svc = new PortalService(
    prisma,
    { verify: async () => true } as any,
    { presignDownloadForRelease: async () => ({ url: 'https://signed' }) } as any,
    { log: async (e: any) => audited.push(e) } as any,
    { get: () => undefined } as any,
    { renderPdf: async () => Buffer.from('%PDF-1.7 test') } as any,
    { incrWithTtl: async () => 1 } as any,
  );
  return { svc, audited, upserts, claimUpdates, tokenUpdates, trusteeUpdates, roster, claim };
}

const heirCtx = (over: Partial<ClaimTokenContext> = {}): ClaimTokenContext => ({
  tokenId: 'tok-1',
  willId: 'will-1',
  claimId: 'claim-1',
  role: 'HEIR' as any,
  scope: 'PORTAL_READ' as any,
  heirContactId: 'heir-1',
  ...over,
});
const trusteeCtx = (over: Partial<ClaimTokenContext> = {}): ClaimTokenContext =>
  heirCtx({ role: 'TRUSTEE' as any, heirContactId: null, ...over });

const META = { ipAddress: '203.0.113.9', userAgent: 'Mozilla/5.0 (test)' };

describe('POST /portal/claim/confirm — heir only, APPROVED only', () => {
  it('records the confirmation against the token’s heir, never a body field', async () => {
    const { svc, upserts } = makeService();
    await expect(svc.confirm(heirCtx(), META)).resolves.toMatchObject({ confirmed: true });
    expect(upserts[0].where.claimId_heirContactId).toEqual({ claimId: 'claim-1', heirContactId: 'heir-1' });
    expect(upserts[0].create).toMatchObject({ ipAddress: '203.0.113.9', userAgent: 'Mozilla/5.0 (test)' });
  });

  // Idempotent by the @@unique([claimId, heirContactId]). A second tap must not rewrite the
  // first confirmation's timestamp or IP — the first one is the evidentiary record.
  it('leaves the original timestamp alone on a repeat tap', async () => {
    const { svc, upserts } = makeService();
    await svc.confirm(heirCtx(), META);
    expect(upserts[0].update).toEqual({});
  });

  it('REFUSES a trustee', async () => {
    const { svc } = makeService();
    await expect(svc.confirm(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  // A HEIR token with no heirContactId cannot be attributed to a roster row, so it cannot
  // be allowed to satisfy a gate that counts roster rows.
  it('REFUSES an heir token that names no heir row', async () => {
    const { svc } = makeService();
    await expect(svc.confirm(heirCtx({ heirContactId: null }), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  for (const status of ['SUBMITTED', 'UNDER_REVIEW', 'REJECTED', 'RELEASED']) {
    it(`REFUSES while the claim is ${status}`, async () => {
      const { svc } = makeService({ status });
      await expect(svc.confirm(heirCtx(), META)).rejects.toBeInstanceOf(BadRequestException);
    });
  }
});

/**
 * Reading a dead person's estate requires having ACCEPTED the trusteeship, not merely having
 * been named to it. The testator's nomination is one half of an appointment; the person's
 * own answer is the other.
 *
 * The reason this needs a route of its own rather than just a check: the release notice
 * sends a trustee to /portal, and the ONLY other way to reach CONFIRMED is the /trustee/:id
 * link from the original invitation — a uuid mailed out when the will was written. Gating
 * reads without offering acceptance here would refuse a trustee who came to do their job,
 * with no route forward from where they are standing. That is a worse failure than the one
 * being fixed, so the two ship together.
 */
describe('a trustee must accept the role before reading the estate', () => {
  const pending = () => ({
    trustees: [{ id: 'trustee-1', phone: '+966555000111', email: 'trustee@x.com', status: 'PENDING' }],
    status: 'RELEASED',
  });

  it('REFUSES the will, the videos and the PDF while PENDING', async () => {
    const { svc } = makeService(pending());
    await expect(svc.will(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(svc.videos(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(svc.pdf(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('tells them how to fix it, and me() flags it before they hit a wall', async () => {
    const { svc } = makeService(pending());
    await expect(svc.will(trusteeCtx(), META)).rejects.toThrow(/accept your trusteeship/i);
    await expect(svc.me(trusteeCtx())).resolves.toMatchObject({ trusteeAcceptancePending: true });
  });

  it('opens the estate once they accept, from inside the portal', async () => {
    const { svc, trusteeUpdates } = makeService(pending());
    await expect(svc.confirmTrusteeship(trusteeCtx(), META)).resolves.toEqual({ confirmed: true });

    // Recorded like TrusteesService.confirm does — this is evidentiary, not a flag.
    expect(trusteeUpdates[0]).toMatchObject({
      status: 'CONFIRMED',
      ipAddress: '203.0.113.9',
      userAgent: 'Mozilla/5.0 (test)',
    });
    await expect(svc.will(trusteeCtx(), META)).resolves.toBeDefined();
    await expect(svc.me(trusteeCtx())).resolves.toMatchObject({ trusteeAcceptancePending: false });
  });

  it('does not rewrite the moment of acceptance on a second tap', async () => {
    const { svc, trusteeUpdates } = makeService(pending());
    await svc.confirmTrusteeship(trusteeCtx(), META);
    await expect(svc.confirmTrusteeship(trusteeCtx(), META)).resolves.toEqual({ confirmed: true });
    expect(trusteeUpdates).toHaveLength(1);
  });

  it('REFUSES an heir asking to accept a trusteeship', async () => {
    const { svc } = makeService(pending());
    await expect(svc.confirmTrusteeship(heirCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  // Heirs are beneficiaries by the terms of the will. There is nothing for them to accept,
  // and gating them would lock out the very people the hand-over exists for.
  it('leaves HEIRS entirely alone', async () => {
    const { svc } = makeService({ status: 'RELEASED' });
    await expect(svc.will(heirCtx(), META)).resolves.toBeDefined();
    await expect(svc.me(heirCtx())).resolves.toMatchObject({ trusteeAcceptancePending: false });
  });
});

describe('POST /portal/claim/override — trustee only, and attributed', () => {
  it('stamps the override against the Trustee row the TOKEN maps to', async () => {
    const { svc, claimUpdates } = makeService();
    await expect(svc.override(trusteeCtx(), META)).resolves.toMatchObject({ overrideActive: true });
    expect(claimUpdates[0].trusteeOverrideBy).toBe('trustee-1');
    expect(claimUpdates[0].trusteeOverrideAt).toBeInstanceOf(Date);
  });

  it('REFUSES an heir', async () => {
    const { svc } = makeService();
    await expect(svc.override(heirCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  // The roster changed under a live session. Refuse rather than stamping an override no
  // trustee row can be held to.
  it('REFUSES when the token’s subject is no longer on the trustee roster', async () => {
    const { svc } = makeService({
      trustees: [{ id: 't-other', phone: '+966555999999', email: 'other@x.com', status: 'CONFIRMED' }],
    });
    await expect(svc.override(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
  });

  // Being ON the roster is the testator's nomination. CONFIRMED is the person's own answer
  // to it. The override removes the heirs' only say in a release, so it has to come from
  // someone who actually accepted the role — not from a name the testator typed years ago.
  //
  // The rest of the codebase already agrees: schema.prisma documents the field as "A
  // CONFIRMED trustee can override", and release() refuses without a CONFIRMED trustee. The
  // sibling gate does NOT cover this case, because a different trustee being confirmed
  // satisfies release() while this one does the overriding.
  it('REFUSES a trustee who never accepted the role', async () => {
    const { svc, claimUpdates } = makeService({
      trustees: [{ id: 'trustee-1', phone: '+966555000111', email: 'trustee@x.com', status: 'PENDING' }],
    });

    await expect(svc.override(trusteeCtx(), META)).rejects.toBeInstanceOf(ForbiddenException);
    expect(claimUpdates).toHaveLength(0); // nothing stamped on the way to refusing
  });

  it('tells the PENDING trustee how to become able to do it', async () => {
    // A bare "forbidden" would read as "you are not the trustee", which is false and would
    // send them to support. They are one code away.
    const { svc } = makeService({
      trustees: [{ id: 'trustee-1', phone: '+966555000111', email: 'trustee@x.com', status: 'PENDING' }],
    });
    await expect(svc.override(trusteeCtx(), META)).rejects.toThrow(/confirm your trusteeship/i);
  });

  // First override wins: the conditional write carries `trusteeOverrideAt: null`, so a
  // second trustee cannot rewrite who is on the hook for the decision.
  it('does not rewrite the attribution of an override already recorded', async () => {
    const { svc, claimUpdates } = makeService({ overrideAt: new Date('2026-01-01') });
    await svc.override(trusteeCtx(), META);
    expect(claimUpdates).toHaveLength(0);
  });
});

describe('POST /portal/exit revokes the session server-side', () => {
  it('burns the token, so the guard refuses it afterwards', async () => {
    const { svc, tokenUpdates } = makeService();
    await expect(svc.exit(heirCtx())).resolves.toEqual({ signedOut: true });
    expect(tokenUpdates[0].consumedAt).toBeInstanceOf(Date);
  });
});

describe('every portal read and write lands in the audit trail', () => {
  it('logs the will read, the videos read, the pdf render, the confirmation and the override', async () => {
    const released = makeService({ status: 'RELEASED' });
    await released.svc.will(heirCtx(), META);
    await released.svc.videos(heirCtx(), META);
    await released.svc.pdf(heirCtx(), META);

    const approved = makeService();
    await approved.svc.confirm(heirCtx(), META);
    await approved.svc.override(trusteeCtx(), META);

    const actions = [...released.audited, ...approved.audited].map((a) => a.action);
    expect(actions).toEqual(
      expect.arrayContaining([
        'portal.will.read',
        'portal.videos.read',
        'portal.will.pdf',
        'portal.heir.confirm_release',
        'portal.trustee.override_release',
      ]),
    );
    // One row per action, not one per session: five actions, five rows. (The videos list
    // is ONE row carrying every fileId in metadata, not a row per file.)
    expect(actions).toHaveLength(5);
    const videosRow = released.audited.find((a) => a.action === 'portal.videos.read');
    expect(videosRow.metadata).toMatchObject({ fileIds: ['file-1'], count: 1 });
  });

  it('records who, what, when and from where', async () => {
    const { svc, audited } = makeService({ status: 'RELEASED' });
    await svc.will(heirCtx(), META);
    expect(audited[0]).toMatchObject({
      actorRole: 'PORTAL_HEIR',
      action: 'portal.will.read',
      targetType: 'Will',
      targetId: 'will-1',
      ipAddress: '203.0.113.9',
      userAgent: 'Mozilla/5.0 (test)',
    });
    expect(audited[0].metadata).toMatchObject({ willId: 'will-1', claimId: 'claim-1', heirContactId: 'heir-1' });
  });

  /**
   * An audit row is read by support staff and survives every rotation. It must not become
   * the place a raw session credential or a full phone number is archived in plaintext.
   */
  it('never writes a raw token or a full contact detail', async () => {
    const { svc, audited } = makeService({
      status: 'RELEASED',
      subject: { subjectEmail: null, subjectPhone: '+966555000111' },
    });
    await svc.will(heirCtx(), META);

    const serialised = JSON.stringify(audited[0]);
    expect(serialised).not.toContain('+966555000111');
    expect(audited[0].metadata.subject).toBe('***0111'); // NotificationsService.maskDestination style
    // The token id is a database handle and is fine; the secret itself never appears.
    expect(audited[0].metadata.tokenId).toBe('tok-1');
    expect(serialised).not.toMatch(/[A-Za-z0-9_-]{43}/);
  });

  /**
   * The portal AWAITS its audit write, so it is worth being explicit about why that cannot
   * strand a grieving family behind a broken logging table: AuditService.log catches and
   * swallows its own failures by design ("writes never throw into the request path"). Driven
   * against the REAL AuditService with a prisma that throws, rather than asserted on trust.
   */
  it('cannot break a read, because AuditService swallows its own failures', async () => {
    const { AuditService } = await import('../common/audit/audit.service');
    const audit = new AuditService({
      auditLog: { create: async () => { throw new Error('audit table gone'); } },
    } as any);
    await expect(audit.log({ action: 'portal.will.read' })).resolves.toBeUndefined();

    const { svc } = makeService({ status: 'RELEASED' });
    (svc as any).audit = audit;
    await expect(svc.will(heirCtx(), META)).resolves.toMatchObject({ personalMessage: 'For my children' });
  });
});
