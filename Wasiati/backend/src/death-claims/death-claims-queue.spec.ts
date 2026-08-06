import { DeathClaimsService, DECIDED_CLAIM_QUEUE_DAYS } from './death-claims.service';

/**
 * The admin claims queue is the ONLY admin surface, so what it lists decides what can
 * happen to a claim at all. The bug this suite pins: the filter used to be
 * `{ SUBMITTED, UNDER_REVIEW }`, so approving a claim made it VANISH from the queue —
 * the Release button could never be reached and no estate was releasable in-product.
 *
 *   1. An APPROVED claim MUST appear (it is awaiting the safety window + release).
 *   2. Recently decided claims appear for DECIDED_CLAIM_QUEUE_DAYS, then drop out —
 *      the queue shows recent outcomes (the prototype renders rejected/released cards)
 *      without accumulating history forever.
 *   3. APPROVED rows carry a releaseGate mirroring release()'s real preconditions.
 */

const DAY = 24 * 60 * 60 * 1000;
const HOUR = 60 * 60 * 1000;

function makeService(rows: any[], config: Record<string, string> = {}) {
  const captured: { where?: any } = {};
  const prisma: any = {
    deathClaim: {
      findMany: async (args: any) => {
        captured.where = args.where;
        return rows;
      },
    },
  };
  const cfg: any = { get: (k: string) => config[k] };
  const svc = new DeathClaimsService(prisma, {} as any, {} as any, {} as any, cfg, {} as any, {} as any);
  return { svc, captured };
}

/** A queue row in the shape the service's findMany include produces. */
function queueRow(over: any = {}) {
  return {
    id: 'c1',
    status: 'APPROVED',
    submittedByName: 'Ali',
    safetyCheckSentAt: new Date(Date.now() - 100 * HOUR),
    trusteeOverrideAt: null,
    reviewedAt: new Date(),
    releasedAt: null,
    will: {
      id: 'w1',
      status: 'SEALED',
      owner: { id: 'o1', email: 'owner@x.com', phone: '+15550001111', region: 'US' },
      heirContacts: [],
      trustees: [{ status: 'CONFIRMED' }],
    },
    heirConfirmations: [],
    ...over,
  };
}

describe('listPendingReview — what the admin queue asks the database for', () => {
  it('includes APPROVED unconditionally: approving a claim must NOT remove it from the queue', async () => {
    const { svc, captured } = makeService([]);
    await svc.listPendingReview();

    const unconditional = captured.where.OR.find((c: any) => c.status?.in);
    expect(unconditional.status.in).toEqual(expect.arrayContaining(['SUBMITTED', 'UNDER_REVIEW', 'APPROVED']));
    // Unconditional means exactly that — no date clause on the active statuses.
    expect(Object.keys(unconditional)).toEqual(['status']);
  });

  it('keeps decided claims only within the window, keyed off the DECISION time', async () => {
    const { svc, captured } = makeService([]);
    const before = Date.now() - DECIDED_CLAIM_QUEUE_DAYS * DAY;
    await svc.listPendingReview();
    const after = Date.now() - DECIDED_CLAIM_QUEUE_DAYS * DAY;

    const rejected = captured.where.OR.find((c: any) => c.status === 'REJECTED');
    const released = captured.where.OR.find((c: any) => c.status === 'RELEASED');
    // REJECTED expires off reviewedAt, RELEASED off releasedAt — not createdAt, or a
    // slow review would expire the moment it concluded.
    expect(rejected.reviewedAt.gte.getTime()).toBeGreaterThanOrEqual(before);
    expect(rejected.reviewedAt.gte.getTime()).toBeLessThanOrEqual(after);
    expect(released.releasedAt.gte.getTime()).toBeGreaterThanOrEqual(before);
    expect(released.releasedAt.gte.getTime()).toBeLessThanOrEqual(after);
  });

  it('never selects the owner row wholesale (passwordHash/mfaSecret must not reach the admin client)', async () => {
    const prisma: any = {
      deathClaim: {
        findMany: async (args: any) => {
          const ownerSelect = args.include.will.select.owner.select;
          expect(ownerSelect).toEqual({ id: true, email: true, phone: true, region: true });
          return [];
        },
      },
    };
    const svc = new DeathClaimsService(prisma, {} as any, {} as any, {} as any, { get: () => undefined } as any, {} as any, {} as any);
    await svc.listPendingReview();
  });
});

describe('listPendingReview — the APPROVED releaseGate mirrors release()', () => {
  it('an APPROVED claim appears WITH a ready releaseGate when every condition holds', async () => {
    const { svc } = makeService([queueRow()]);
    const [row] = (await svc.listPendingReview()) as any[];

    expect(row.status).toBe('APPROVED');
    expect(row.releaseGate).toMatchObject({
      safetyWindowElapsed: true,
      willSealed: true,
      trusteeConfirmed: true,
      heirsSatisfied: true,
      ready: true,
    });
    expect(row.releaseGate.releasableAt).toBeInstanceOf(Date);
  });

  it('reports NOT ready while the safety window is still running, with the exact time it opens', async () => {
    const sentAt = new Date(Date.now() - 1 * HOUR);
    const { svc } = makeService([queueRow({ safetyCheckSentAt: sentAt })]);
    const [row] = (await svc.listPendingReview()) as any[];

    expect(row.releaseGate.safetyWindowElapsed).toBe(false);
    expect(row.releaseGate.ready).toBe(false);
    expect(row.releaseGate.releasableAt.getTime()).toBe(sentAt.getTime() + 72 * HOUR); // default window
  });

  it('honours DEATH_CLAIM_SAFETY_WINDOW_HOURS in releasableAt', async () => {
    const sentAt = new Date(Date.now() - 5 * HOUR);
    const { svc } = makeService([queueRow({ safetyCheckSentAt: sentAt })], {
      DEATH_CLAIM_SAFETY_WINDOW_HOURS: '4',
    });
    const [row] = (await svc.listPendingReview()) as any[];
    expect(row.releaseGate.releasableAt.getTime()).toBe(sentAt.getTime() + 4 * HOUR);
    expect(row.releaseGate.safetyWindowElapsed).toBe(true);
  });

  it('counts outstanding reachable heirs and flips heirsSatisfied on a trustee override', async () => {
    const heirs = [
      { id: 'h1', name: 'A', relation: 'SON', phone: '+1555', email: null, isMinor: false }, // reachable, unconfirmed
      { id: 'h2', name: 'B', relation: 'DAUGHTER', phone: null, email: 'b@x.com', isMinor: false }, // reachable, confirmed
      { id: 'h3', name: 'C', relation: 'SON', phone: null, email: null, isMinor: true }, // minor — not waited on
    ];
    const confirmations = [{ heirContactId: 'h2', confirmedAt: new Date() }];

    const blocked = queueRow({ will: { ...queueRow().will, heirContacts: heirs }, heirConfirmations: confirmations });
    const { svc } = makeService([blocked]);
    const [row] = (await svc.listPendingReview()) as any[];
    expect(row.releaseGate.outstandingHeirConfirmations).toBe(1);
    expect(row.releaseGate.heirsSatisfied).toBe(false);
    expect(row.releaseGate.ready).toBe(false);
    expect(row.releaseGate.heirs).toHaveLength(3);

    // And NOT who they are. assertHeirGateSatisfied refuses to name heirs to an admin
    // because "the roster of a private will is not theirs to read"; this payload used to
    // hand the same admin every name and relationship anyway. An operator needs counts and
    // releasability, not the deceased's children.
    for (const h of row.releaseGate.heirs) {
      expect(h).not.toHaveProperty('name');
      expect(h).not.toHaveProperty('relation');
      expect(JSON.stringify(h)).not.toContain('DAUGHTER');
    }

    const overridden = queueRow({
      trusteeOverrideAt: new Date(),
      will: { ...queueRow().will, heirContacts: heirs },
      heirConfirmations: confirmations,
    });
    const { svc: svc2 } = makeService([overridden]);
    const [row2] = (await svc2.listPendingReview()) as any[];
    expect(row2.releaseGate.overrideActive).toBe(true);
    expect(row2.releaseGate.heirsSatisfied).toBe(true);
    expect(row2.releaseGate.ready).toBe(true);
  });

  it('non-APPROVED rows carry releaseGate: null and keep the shape the admin client parses', async () => {
    const { svc } = makeService([queueRow({ status: 'SUBMITTED', safetyCheckSentAt: null })]);
    const [row] = (await svc.listPendingReview()) as any[];
    expect(row.releaseGate).toBeNull();
    // The Flutter DeathClaim.fromJson reads will.owner.email — that path must survive.
    expect(row.will.owner.email).toBe('owner@x.com');
    // The raw rosters are folded into releaseGate, not dumped on the will object.
    expect(row.will.heirContacts).toBeUndefined();
    expect(row.will.trustees).toBeUndefined();
  });
});
