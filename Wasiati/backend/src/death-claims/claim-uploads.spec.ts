import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { createHash } from 'crypto';
import { ClaimUploadsController, CLAIM_UPLOAD_OPERATION_CAP, CLAIM_CONFIRM_CAP } from './claim-uploads.controller';
import { ClaimScopes, ClaimTokenContext, ClaimTokenGuard, CLAIM_TOKEN_HEADER } from './claim-token.guard';
import { FilesService } from '../files/files.service';

/**
 * The accountless death-certificate upload path.
 *
 * This is a write endpoint reachable with NO login, so the tests below are about what it
 * REFUSES. Each one is written to fail if its specific guard were removed:
 *   - the hardcoded kind (revert it to `dto.kind` and the video_legacy tests pass an upload);
 *   - the willId-from-token rule (accept a willId from the body and the cross-estate test
 *     stops throwing);
 *   - the expiry / consumed / scope checks in the guard;
 *   - the atomic upload cap.
 */

const HOUR = 60 * 60 * 1000;
const RAW_TOKEN = 'w0Kx8dQ2gYb7pR4tLmN1sVzC5hJ6aE3fUiO9nXqB2yA';
const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

const OWNER = 'owner-1';
const OTHER_OWNER = 'owner-2';

function tokenRow(over: Partial<Record<string, any>> = {}) {
  return {
    id: 'tok-1',
    tokenHash: sha256(RAW_TOKEN),
    willId: 'will-1',
    claimId: null,
    role: 'WITNESS',
    scope: 'CLAIM_SUBMIT',
    subjectPhone: '+971500000000',
    subjectEmail: null,
    heirContactId: null,
    expiresAt: new Date(Date.now() + 24 * HOUR),
    consumedAt: null,
    uploadCount: 0,
    confirmCount: 0,
    createdAt: new Date(),
    ...over,
  };
}

/** A prisma double whose claimAccessToken.updateMany honours the same WHERE the real one would. */
function makePrisma(row: any, wills: Record<string, { ownerId: string }> = { 'will-1': { ownerId: OWNER } }) {
  const created: any[] = [];
  const prisma: any = {
    claimAccessToken: {
      findUnique: async ({ where }: any) => (row && where.tokenHash === row.tokenHash ? row : null),
      updateMany: async ({ where, data }: any) => {
        if (!row || where.id !== row.id) return { count: 0 };
        if (where.consumedAt === null && row.consumedAt !== null) return { count: 0 };
        if (where.uploadCount?.lt !== undefined && !(row.uploadCount < where.uploadCount.lt)) return { count: 0 };
        if (where.uploadCount?.gt !== undefined && !(row.uploadCount > where.uploadCount.gt)) return { count: 0 };
        // confirmCount is its own budget: presign retries must not eat the one confirm.
        if (where.confirmCount?.lt !== undefined && !(row.confirmCount < where.confirmCount.lt)) return { count: 0 };
        if (data.uploadCount?.increment) row.uploadCount += data.uploadCount.increment;
        if (data.uploadCount?.decrement) row.uploadCount -= data.uploadCount.decrement;
        if (data.confirmCount?.increment) row.confirmCount += data.confirmCount.increment;
        return { count: 1 };
      },
    },
    will: { findUnique: async ({ where }: any) => wills[where.id] ?? null },
    // Uploads are refused once an account is scheduled for posthumous purge. A death
    // certificate is uploaded while the CLAIM is still open — release (which sets
    // scheduledPurgeAt) happens later — so the estate here is not yet winding down.
    user: { findUnique: async () => ({ scheduledPurgeAt: null }) },
    fileObject: {
      aggregate: async () => ({ _sum: { sizeBytes: 0 } }),
      create: async ({ data }: any) => {
        created.push(data);
        return { id: `f${created.length}`, ...data };
      },
    },
    // confirmUpload wraps the quota check + insert in a transaction; run the callback inline.
    $transaction: async (fn: any) => fn(prisma),
  };
  return { prisma, created };
}

/**
 * The REAL FilesService, not a double. The point of several tests is that the content-type
 * allow-list and per-kind size cap actually run against the kind this controller chose — a
 * stub that records arguments could not show that a leaked `kind` would have been accepted.
 */
function makeFiles(prisma: any) {
  const storage: any = {
    configured: true,
    presignUpload: async ({ key }: any) => ({
      uploadUrl: `https://storage.test/${key}`,
      key,
      requiredHeaders: {},
      expiresInSeconds: 900,
    }),
  };
  const config: any = { get: () => undefined };
  return new FilesService(storage, prisma, config, { hasFeature: async () => true } as any);
}

function makeController(row: any, wills?: Record<string, { ownerId: string }>) {
  const { prisma, created } = makePrisma(row, wills);
  const controller = new ClaimUploadsController(makeFiles(prisma), prisma);
  return { controller, prisma, created, row };
}

/** The context the guard would have attached for `row`. */
const ctxFor = (row: any): ClaimTokenContext => ({
  tokenId: row.id,
  willId: row.willId,
  claimId: row.claimId,
  role: row.role,
  scope: row.scope,
  heirContactId: row.heirContactId,
});

// --- guard ------------------------------------------------------------------------------

/** A fake ExecutionContext carrying `headers`, with the route's declared scopes in metadata. */
function execContext(headers: Record<string, string>, handler: any = () => undefined) {
  const request: any = { headers };
  const ctx = {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => handler,
    getClass: () => ClaimUploadsController,
  } as unknown as ExecutionContext;
  return { ctx, request };
}

function makeGuard(row: any) {
  const { prisma } = makePrisma(row);
  return new ClaimTokenGuard(new Reflector(), prisma);
}

describe('ClaimTokenGuard', () => {
  it('admits a valid CLAIM_SUBMIT token and attaches the estate from the TOKEN', async () => {
    const row = tokenRow();
    const { ctx, request } = execContext({ [CLAIM_TOKEN_HEADER]: RAW_TOKEN });
    await expect(makeGuard(row).canActivate(ctx)).resolves.toBe(true);
    expect(request.claimToken).toEqual({
      tokenId: 'tok-1',
      willId: 'will-1',
      claimId: null,
      role: 'WITNESS',
      scope: 'CLAIM_SUBMIT',
      heirContactId: null,
    });
    // Never mistaken for a signed-in account.
    expect(request.user).toBeUndefined();
  });

  it('REFUSES an EXPIRED token', async () => {
    const row = tokenRow({ expiresAt: new Date(Date.now() - 1000) });
    const { ctx } = execContext({ [CLAIM_TOKEN_HEADER]: RAW_TOKEN });
    await expect(makeGuard(row).canActivate(ctx)).rejects.toThrow(UnauthorizedException);
  });

  it('REFUSES a CONSUMED token', async () => {
    const row = tokenRow({ consumedAt: new Date() });
    const { ctx } = execContext({ [CLAIM_TOKEN_HEADER]: RAW_TOKEN });
    await expect(makeGuard(row).canActivate(ctx)).rejects.toThrow(UnauthorizedException);
  });

  it('REFUSES an unknown token, and a missing header', async () => {
    const row = tokenRow();
    await expect(makeGuard(row).canActivate(execContext({ [CLAIM_TOKEN_HEADER]: 'not-a-token' }).ctx)).rejects.toThrow(
      UnauthorizedException,
    );
    await expect(makeGuard(row).canActivate(execContext({}).ctx)).rejects.toThrow(UnauthorizedException);
  });

  it('REFUSES an absurdly long header without hashing it', async () => {
    const row = tokenRow();
    const { ctx } = execContext({ [CLAIM_TOKEN_HEADER]: 'x'.repeat(100_000) });
    await expect(makeGuard(row).canActivate(ctx)).rejects.toThrow(UnauthorizedException);
  });

  it('REFUSES a PORTAL_READ token on a CLAIM_SUBMIT route (scope crossing)', async () => {
    const row = tokenRow({ scope: 'PORTAL_READ', claimId: 'claim-1', role: 'HEIR' });
    const { ctx } = execContext({ [CLAIM_TOKEN_HEADER]: RAW_TOKEN });
    await expect(makeGuard(row).canActivate(ctx)).rejects.toThrow(ForbiddenException);
  });

  it('REFUSES a CLAIM_SUBMIT token on a PORTAL_READ route (the reverse crossing)', async () => {
    // A route that declares only PORTAL_READ, e.g. a future heir-portal read.
    class PortalRoutes {
      @ClaimScopes('PORTAL_READ' as any)
      read() {}
    }
    const handler = PortalRoutes.prototype.read;
    const row = tokenRow(); // CLAIM_SUBMIT
    const { ctx } = execContext({ [CLAIM_TOKEN_HEADER]: RAW_TOKEN }, handler);
    // getClass must not leak the upload controller's CLAIM_SUBMIT metadata into this route.
    const guardCtx = {
      switchToHttp: () => ({ getRequest: () => ({ headers: { [CLAIM_TOKEN_HEADER]: RAW_TOKEN } }) }),
      getHandler: () => handler,
      getClass: () => PortalRoutes,
    } as unknown as ExecutionContext;
    void ctx;
    await expect(makeGuard(row).canActivate(guardCtx)).rejects.toThrow(ForbiddenException);
  });

  it('FAILS CLOSED on a route that declares no scope at all', async () => {
    class Undeclared {
      route() {}
    }
    const guardCtx = {
      switchToHttp: () => ({ getRequest: () => ({ headers: { [CLAIM_TOKEN_HEADER]: RAW_TOKEN } }) }),
      getHandler: () => Undeclared.prototype.route,
      getClass: () => Undeclared,
    } as unknown as ExecutionContext;
    await expect(makeGuard(tokenRow()).canActivate(guardCtx)).rejects.toThrow(ForbiddenException);
  });
});

// --- kind is nailed shut ------------------------------------------------------------------

describe('ClaimUploadsController — kind is fixed server-side', () => {
  it('CANNOT presign video_legacy even when the body says so', async () => {
    const row = tokenRow();
    const { controller } = makeController(row);
    // video/mp4 + a 100 MB size are legal for video_legacy and illegal for death_certificate.
    // If `kind` were read from the body this would succeed.
    await expect(
      controller.presign(ctxFor(row), {
        kind: 'video_legacy',
        contentType: 'video/mp4',
        sizeBytes: 100 * 1024 * 1024,
      } as any),
    ).rejects.toThrow(/Unsupported file type/i);
  });

  it('CANNOT presign id_document even when the body says so — the object lands as a death_certificate', async () => {
    const row = tokenRow();
    const { controller } = makeController(row);
    const res = await controller.presign(ctxFor(row), {
      kind: 'id_document',
      contentType: 'application/pdf',
      sizeBytes: 1024,
    } as any);
    // id_document and death_certificate share a content-type list, so the proof is the KEY
    // prefix and the returned kind, both chosen from the hardcoded kind.
    expect(res.kind).toBe('death_certificate');
    expect(res.key.startsWith('death-certificates/')).toBe(true);
    expect(res.key).not.toContain('id-documents/');
  });

  it('CANNOT confirm a body-supplied kind into a video_legacy row', async () => {
    const row = tokenRow();
    const { controller, created } = makeController(row);
    await controller.confirm(ctxFor(row), {
      kind: 'video_legacy',
      key: `death-certificates/${OWNER}/abc.pdf`,
      contentType: 'application/pdf',
      sizeBytes: 1024,
    } as any);
    expect(created).toHaveLength(1);
    expect(created[0].kind).toBe('death_certificate');
  });

  it('refuses a size over the death_certificate cap even though video_legacy allows it', async () => {
    const row = tokenRow();
    const { controller } = makeController(row);
    await expect(
      controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 200 * 1024 * 1024 } as any),
    ).rejects.toThrow(/too large/i);
  });
});

// --- estate scoping -----------------------------------------------------------------------

describe('ClaimUploadsController — cannot touch another estate', () => {
  it('namespaces the key under the OWNER named by the token, not the caller', async () => {
    const row = tokenRow();
    const { controller } = makeController(row, { 'will-1': { ownerId: OWNER }, 'will-2': { ownerId: OTHER_OWNER } });
    const res = await controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 1024 } as any);
    expect(res.key).toBe(`death-certificates/${OWNER}/${res.key.split('/')[2]}`);
    expect(res.key).not.toContain(OTHER_OWNER);
  });

  it('REFUSES to confirm a key belonging to ANOTHER estate', async () => {
    const row = tokenRow();
    const { controller, created } = makeController(row, {
      'will-1': { ownerId: OWNER },
      'will-2': { ownerId: OTHER_OWNER },
    });
    await expect(
      controller.confirm(ctxFor(row), {
        key: `death-certificates/${OTHER_OWNER}/stolen.pdf`,
        contentType: 'application/pdf',
        sizeBytes: 1024,
      } as any),
    ).rejects.toThrow(/does not belong to you/i);
    expect(created).toHaveLength(0);
  });

  it('REFUSES to confirm a key under a NON-certificate prefix of the same owner', async () => {
    const row = tokenRow();
    const { controller, created } = makeController(row);
    await expect(
      controller.confirm(ctxFor(row), {
        key: `legacy-videos/${OWNER}/private.mp4`,
        contentType: 'video/mp4',
        sizeBytes: 1024,
      } as any),
    ).rejects.toThrow(/does not belong to this claim/i);
    expect(created).toHaveLength(0);
  });

  it('two tokens for two estates get disjoint namespaces, and neither can write into the other', async () => {
    const wills = { 'will-1': { ownerId: OWNER }, 'will-2': { ownerId: OTHER_OWNER } };
    const rowA = tokenRow();
    const rowB = tokenRow({ id: 'tok-2', willId: 'will-2' });
    const a = makeController(rowA, wills);
    const b = makeController(rowB, wills);

    const keyA = (await a.controller.presign(ctxFor(rowA), { contentType: 'application/pdf', sizeBytes: 1 } as any))
      .key;
    const keyB = (await b.controller.presign(ctxFor(rowB), { contentType: 'application/pdf', sizeBytes: 1 } as any))
      .key;
    expect(keyA.startsWith(`death-certificates/${OWNER}/`)).toBe(true);
    expect(keyB.startsWith(`death-certificates/${OTHER_OWNER}/`)).toBe(true);

    // Estate A's token handed estate B's key: refused. There is no body field that could
    // have aimed it there — the owner is resolved from the token's willId alone.
    await expect(
      a.controller.confirm(ctxFor(rowA), { key: keyB, contentType: 'application/pdf', sizeBytes: 1 } as any),
    ).rejects.toThrow(/does not belong to you/i);
    expect(a.created).toHaveLength(0);
  });

  it('IGNORES a willId smuggled into the body — the estate comes from the token only', async () => {
    const wills = { 'will-1': { ownerId: OWNER }, 'will-2': { ownerId: OTHER_OWNER } };
    const row = tokenRow(); // token is for will-1
    const { controller } = makeController(row, wills);
    const res = await controller.presign(ctxFor(row), {
      willId: 'will-2', // whitelist:true strips this; nothing reads it either way
      contentType: 'application/pdf',
      sizeBytes: 1024,
    } as any);
    expect(res.key.startsWith(`death-certificates/${OWNER}/`)).toBe(true);
    expect(res.key).not.toContain(OTHER_OWNER);
  });

  it('404s a token whose estate no longer exists, rather than falling back to any owner', async () => {
    const row = tokenRow({ willId: 'will-gone' });
    const { controller } = makeController(row, { 'will-1': { ownerId: OWNER } });
    await expect(
      controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 1024 } as any),
    ).rejects.toThrow(/no longer valid/i);
  });
});

// --- the upload cap -----------------------------------------------------------------------

describe('ClaimUploadsController — upload cap', () => {
  it('lets a valid token presign + confirm EXACTLY ONE death certificate', async () => {
    const row = tokenRow();
    const { controller, created } = makeController(row);
    const presigned = await controller.presign(ctxFor(row), {
      contentType: 'application/pdf',
      sizeBytes: 2048,
    } as any);
    expect(presigned.key.startsWith(`death-certificates/${OWNER}/`)).toBe(true);

    const confirmed: any = await controller.confirm(ctxFor(row), {
      key: presigned.key,
      contentType: 'application/pdf',
      sizeBytes: 2048,
    } as any);
    expect(confirmed.kind).toBe('death_certificate');
    expect(confirmed.userId).toBe(OWNER);
    expect(created).toHaveLength(1);
    expect(row.uploadCount).toBe(1);
    expect(row.confirmCount).toBe(CLAIM_CONFIRM_CAP);

    // ...and nothing more. A second CERTIFICATE is refused — that is the real invariant,
    // and it is now enforced where it happens rather than inferred from an operation count.
    await expect(
      controller.confirm(ctxFor(row), {
        key: presigned.key,
        contentType: 'application/pdf',
        sizeBytes: 2048,
      } as any),
    ).rejects.toThrow(/already been used/i);
    expect(created).toHaveLength(1);
  });

  // THE BUG THIS SPLIT EXISTS FOR.
  //
  // The client's PUT to storage happens between presign and confirm. When it drops, the
  // server never hears about it, so there is nothing to refund. Under one shared budget of
  // two, the retry's presign spent the last slot and confirm was then refused: no
  // certificate stored, no way forward, and the screen still offering the button that had
  // just burned the link. A bereaved daughter on poor coverage was locked out of filing at
  // all, and her only route back was a fresh link — capped at 3 per will per day.
  it('lets a claimant RETRY after an upload drops mid-transfer', async () => {
    const row = tokenRow();
    const { controller, created } = makeController(row);

    // First attempt: presigned, and then the bytes never arrive. Nothing tells the server.
    const first = await controller.presign(ctxFor(row), {
      contentType: 'application/pdf',
      sizeBytes: 2048,
    } as any);
    expect(first.key).toBeDefined();

    // She taps attach again. This must work, and it must end with a stored certificate.
    const second = await controller.presign(ctxFor(row), {
      contentType: 'application/pdf',
      sizeBytes: 2048,
    } as any);
    const confirmed: any = await controller.confirm(ctxFor(row), {
      key: second.key,
      contentType: 'application/pdf',
      sizeBytes: 2048,
    } as any);

    expect(confirmed.kind).toBe('death_certificate');
    expect(created).toHaveLength(1);
  });

  it('still bounds a leaked token: presigns run out, and say so honestly', async () => {
    const row = tokenRow();
    const { controller } = makeController(row);
    for (let i = 0; i < CLAIM_UPLOAD_OPERATION_CAP; i++) {
      await controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 1024 } as any);
    }
    expect(row.uploadCount).toBe(CLAIM_UPLOAD_OPERATION_CAP);

    // Distinct wording on purpose: running out of ATTEMPTS is not the same situation as
    // having already sent a document, and telling someone their link is spent when they
    // have not managed to send anything is both untrue and where they give up.
    await expect(
      controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 1024 } as any),
    ).rejects.toThrow(/too many upload attempts/i);
  });

  it('caps CONFIRM too — phantom keys cannot be used to drain the estate quota', async () => {
    const row = tokenRow({ confirmCount: CLAIM_CONFIRM_CAP });
    const { controller, created } = makeController(row);
    await expect(
      controller.confirm(ctxFor(row), {
        key: `death-certificates/${OWNER}/ghost.pdf`,
        contentType: 'application/pdf',
        sizeBytes: 1024 * 1024 * 1024,
      } as any),
    ).rejects.toThrow(/already been used/i);
    expect(created).toHaveLength(0);
  });

  it('does NOT burn a slot when the presign is REJECTED', async () => {
    const row = tokenRow();
    const { controller } = makeController(row);
    await expect(
      controller.presign(ctxFor(row), { contentType: 'application/zip', sizeBytes: 1024 } as any),
    ).rejects.toThrow(/Unsupported file type/i);
    expect(row.uploadCount).toBe(0); // refunded — a rejected presign granted no write URL
    // so the real upload still goes through.
    await expect(
      controller.presign(ctxFor(row), { contentType: 'application/pdf', sizeBytes: 1024 } as any),
    ).resolves.toBeDefined();
  });
});
