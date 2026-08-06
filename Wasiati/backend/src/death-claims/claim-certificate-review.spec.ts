import { NotFoundException } from '@nestjs/common';
import { DeathClaimsService } from './death-claims.service';

/**
 * The reviewer has to be able to SEE the death certificate.
 *
 * submitClaim's own comment describes the queue as one "a human is about to open", and the
 * whole anti-fraud design leans on that: approve starts a 72h window, and three days later
 * release hands over an estate. But the claim only stored
 * `${APP_BASE_URL}/files/<id>/download`, and the sole route of that shape is owner-scoped —
 * it loads the row and refuses unless `file.userId === callerId`. Claim uploads are
 * attributed to the DECEASED owner, so there was no request any admin could make that
 * returned those bytes. The gate was performed blind.
 *
 * These tests pin the new door: it resolves through the estate, it refuses rather than
 * fabricating a link when the file cannot be resolved, and it does not become a way to read
 * one estate's documents by quoting another estate's claim.
 */
function makeService(opts: { claim?: any } = {}) {
  const asked: { ownerId: string; fileId: string }[] = [];
  const prisma: any = {
    deathClaim: { findUnique: async () => opts.claim ?? null },
  };
  const files: any = {
    presignDownloadForClaimReview: async (ownerId: string, fileId: string) => {
      asked.push({ ownerId, fileId });
      return { url: 'https://storage.example/signed' };
    },
  };
  const svc = new DeathClaimsService(
    prisma,
    {} as any,
    {} as any,
    {} as any,
    { get: () => undefined } as any,
    {} as any,
    files,
  );
  return { svc, asked };
}

const claim = (over: any = {}) => ({
  certificateFileId: 'file-1',
  will: { ownerId: 'owner-1' },
  ...over,
});

describe('the admin can open the certificate they are deciding on', () => {
  it('returns a signed URL, resolved through the ESTATE that owns the file', async () => {
    const { svc, asked } = makeService({ claim: claim() });

    await expect(svc.certificateForReview('c1')).resolves.toEqual({ url: 'https://storage.example/signed' });

    // The ownerId comes off the claim's will, not from the caller. That is what stops one
    // claim id being used to fetch a different estate's document through a mismatched row.
    expect(asked).toEqual([{ ownerId: 'owner-1', fileId: 'file-1' }]);
  });

  it('404s for a claim that does not exist', async () => {
    const { svc, asked } = makeService({ claim: null });
    await expect(svc.certificateForReview('nope')).rejects.toBeInstanceOf(NotFoundException);
    expect(asked).toEqual([]);
  });

  it('REFUSES, loudly, when the claim has no resolvable certificate', async () => {
    // Only reachable for rows written before the id was stored whose URL did not match the
    // backfill. The reviewer must be told the document cannot be produced — a broken link,
    // or a silent empty state, reads as "nothing to see" and gets approved anyway.
    const { svc, asked } = makeService({ claim: claim({ certificateFileId: null }) });

    await expect(svc.certificateForReview('c1')).rejects.toThrow(/no resolvable certificate/i);
    // And it says what to do about it, rather than only what is wrong.
    await expect(svc.certificateForReview('c1')).rejects.toThrow(/do not approve/i);
    expect(asked).toEqual([]);
  });

  it('never invents a URL of its own — every link comes from the storage layer', async () => {
    // The old certificateFileUrl was built by string concatenation and pointed at a route
    // nobody could use. Anything this method hands back must be a real presigned URL.
    const { svc } = makeService({ claim: claim() });
    const res = await svc.certificateForReview('c1');
    expect(res.url).toBe('https://storage.example/signed');
    expect(res.url).not.toContain('/files/');
  });
});
