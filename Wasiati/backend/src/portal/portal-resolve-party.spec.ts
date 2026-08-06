import { PortalService } from './portal.service';
import { ClaimRole } from '@prisma/client';

/**
 * Which claim a portal sign-in binds to. The old resolveParty was `findFirst` ordered by
 * `createdAt desc` with NO status filter and no scoping — the globally most-recent claim
 * anywhere this email appeared. Two real failures are pinned here:
 *
 *   1. DUPLICATE-CLAIM DEADLOCK: a newer SUBMITTED duplicate on the SAME will eclipsed
 *      the APPROVED claim whose heir roll-call gates release, so confirm() refused every
 *      heir and release deadlocked.
 *   2. CROSS-ESTATE ECLIPSE: an heir on two estates got whichever claim was filed last;
 *      a fresh claim on estate B hid RELEASED estate A until the purge destroyed it.
 *
 * Selection is now status-priority (APPROVED > RELEASED > UNDER_REVIEW > SUBMITTED >
 * REJECTED), recency only within a status. Driven through verify(), resolveParty's
 * public caller, so the test also proves the chosen claim is what the session binds to.
 */

function will(id: string, ownerEmail: string, heirEmail: string) {
  return {
    owner: { email: ownerEmail },
    heirContacts: [{ id: `heir-of-${id}`, phone: null, email: heirEmail }],
    trustees: [],
  };
}

/** claim rows in the shape resolveParty's findMany include produces */
function claim(id: string, status: string, willId: string, createdAt: Date, w: any) {
  return { id, status, willId, createdAt, will: w };
}

function makeService(claims: any[]) {
  const created: any[] = [];
  const prisma: any = {
    deathClaim: {
      // The service sorts in JS; the mock honours the query's createdAt desc order.
      findMany: async () => [...claims].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()),
    },
    claimAccessToken: { create: async (a: any) => created.push(a.data) },
  };
  const otp: any = { issue: async () => '123456', verify: async () => true };
  const svc = new PortalService(
    prisma,
    otp,
    {} as any,
    { log: async () => undefined } as any,
    { get: () => undefined } as any,
    {} as any,
    { incrWithTtl: async () => 1 } as any,
  );
  return { svc, created };
}

const HEIR = 'heir@x.com';
const DAY = 24 * 60 * 60 * 1000;
const T0 = new Date('2026-07-01T00:00:00Z');
const at = (days: number) => new Date(T0.getTime() + days * DAY);

describe('resolveParty picks the claim the portal can DO something with', () => {
  it('a newer duplicate claim on the same will does NOT eclipse the APPROVED one (deadlock case)', async () => {
    const w = will('A', 'owner-a@x.com', HEIR);
    const { svc, created } = makeService([
      claim('claim-approved', 'APPROVED', 'will-A', at(0), w),
      claim('claim-duplicate', 'SUBMITTED', 'will-A', at(5), w), // newer — used to win
    ]);

    const res = await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res.claimStatus).toBe('APPROVED');
    // The session token is minted against the APPROVED claim, so confirm() will accept it.
    expect(created[0].claimId).toBe('claim-approved');
  });

  it('a fresh claim on estate B does not hide RELEASED estate A (two-estates case)', async () => {
    const { svc, created } = makeService([
      claim('claim-a', 'RELEASED', 'will-A', at(0), will('A', 'owner-a@x.com', HEIR)),
      claim('claim-b', 'SUBMITTED', 'will-B', at(10), will('B', 'owner-b@x.com', HEIR)), // newer
    ]);

    const res = await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res.claimStatus).toBe('RELEASED');
    expect(res.estateName).toBe('owner-a@x.com');
    expect(created[0].claimId).toBe('claim-a');
    expect(created[0].willId).toBe('will-A');
    // And the bound party is the roster row on THAT will, not the other estate's.
    expect(created[0].heirContactId).toBe('heir-of-A');
  });

  it('an estate needing this heir\'s confirmation outranks one that is already released', async () => {
    const { svc, created } = makeService([
      claim('claim-released', 'RELEASED', 'will-A', at(10), will('A', 'owner-a@x.com', HEIR)),
      claim('claim-approved', 'APPROVED', 'will-B', at(0), will('B', 'owner-b@x.com', HEIR)),
    ]);
    const res = await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res.claimStatus).toBe('APPROVED');
    expect(created[0].claimId).toBe('claim-approved');
  });

  it('REJECTED loses to anything live, but still binds when it is all there is', async () => {
    const wA = will('A', 'owner-a@x.com', HEIR);
    const { svc } = makeService([
      claim('claim-rejected', 'REJECTED', 'will-A', at(10), wA), // newer
      claim('claim-live', 'SUBMITTED', 'will-A', at(0), wA),
    ]);
    const res = await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res.claimStatus).toBe('SUBMITTED');

    // Alone, the rejected claim is still resolvable — the portal's status screen is how
    // the family learns the outcome at all.
    const { svc: svc2 } = makeService([claim('claim-rejected', 'REJECTED', 'will-A', at(10), wA)]);
    const res2 = await svc2.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res2.claimStatus).toBe('REJECTED');
  });

  it('within one status, recency still decides', async () => {
    const wA = will('A', 'owner-a@x.com', HEIR);
    const { svc, created } = makeService([
      claim('older', 'SUBMITTED', 'will-A', at(0), wA),
      claim('newer', 'SUBMITTED', 'will-A', at(3), wA),
    ]);
    await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(created[0].claimId).toBe('newer');
  });

  it('a claim whose roster no longer matches is skipped, not fatal', async () => {
    // Highest-priority claim's will roster has someone ELSE (roster edited after filing);
    // the next candidate must still resolve.
    const { svc, created } = makeService([
      claim('claim-approved', 'APPROVED', 'will-A', at(0), will('A', 'owner-a@x.com', 'someone-else@x.com')),
      claim('claim-released', 'RELEASED', 'will-B', at(1), will('B', 'owner-b@x.com', HEIR)),
    ]);
    const res = await svc.verify(ClaimRole.HEIR, HEIR, '123456');
    expect(res.claimStatus).toBe('RELEASED');
    expect(created[0].claimId).toBe('claim-released');
  });
});
