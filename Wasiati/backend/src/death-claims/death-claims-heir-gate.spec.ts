import { DeathClaimsService } from './death-claims.service';

/**
 * THE HEIR RELEASE GATE.
 *
 * "The will is released once every registered heir confirms — or the trustee overrides."
 * Release is irreversible and starts a 90-day purge clock, so the people the estate belongs
 * to get a say before it fires.
 *
 * The gate is only a safeguard if its escape hatches work. Two exclusions decide whether it
 * protects a family or locks them out permanently:
 *   - MINORS are never waited on (they cannot consent, and their contacts route to a
 *     guardian);
 *   - an heir with NEITHER a phone NOR an email is never waited on, because they cannot be
 *     asked at all.
 * And if NOBODY is reachable the gate is VACUOUS — otherwise a will whose heirs were
 * entered without contact details could never be released, and the safeguard would turn
 * into total data loss when the purge job ran.
 */
const HOUR = 60 * 60 * 1000;

function makeService(opts: { heirs?: any[]; confirmations?: string[]; overrideAt?: Date | null } = {}) {
  const updates: any[] = [];
  const claim = {
    id: 'c1',
    status: 'APPROVED',
    safetyCheckSentAt: new Date(Date.now() - 100 * HOUR),
    trusteeOverrideAt: opts.overrideAt ?? null,
    submittedByPhone: '+15551111111',
    will: {
      id: 'w1',
      ownerId: 'owner-1',
      status: 'SEALED',
      owner: { email: 'owner@x.com' },
      trustees: [{ status: 'CONFIRMED' }],
      heirContacts: opts.heirs ?? [],
    },
  };
  const prisma: any = {
    deathClaim: {
      findUnique: async () => claim,
      // Honours `where.status` — see the note in death-claims-release.spec.ts.
      updateMany: async ({ where, data }: any) => {
        if (where?.status && where.status !== claim?.status) return { count: 0 };
        updates.push(data);
        return { count: 1 };
      },
      update: async ({ data }: any) => {
        updates.push(data);
        return { id: 'c1', ...data };
      },
    },
    heirReleaseConfirmation: {
      findMany: async () => (opts.confirmations ?? []).map((heirContactId) => ({ heirContactId })),
    },
    user: { update: async () => ({}), findMany: async () => [] },
    will: { findUnique: async () => ({ id: 'w1' }) },
  };
  const notifications: any = { sendEmail: async () => undefined, sendSms: async () => undefined };
  const retention: any = { purgeDeadline: () => new Date(), sendReleaseNotice: async () => undefined };
  const svc = new DeathClaimsService(
    prisma,
    notifications,
    { verify: async () => true } as any,
    retention,
    { get: () => undefined } as any,
    { incrWithTtl: async () => 1 } as any,
    {} as any,
  );
  return { svc, updates };
}

const heir = (id: string, over: any = {}) => ({
  id,
  isMinor: false,
  phone: '+966555000001',
  email: `${id}@x.com`,
  ...over,
});

const released = (updates: any[]) => updates.some((u) => u.status === 'RELEASED');

describe('release is blocked until every reachable heir has confirmed', () => {
  it('REFUSES while a reachable heir has not confirmed', async () => {
    const { svc, updates } = makeService({ heirs: [heir('h1'), heir('h2')], confirmations: ['h1'] });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/have not confirmed/i);
    expect(released(updates)).toBe(false); // and nothing was released
  });

  it('RELEASES once the last outstanding heir confirms', async () => {
    const { svc, updates } = makeService({ heirs: [heir('h1'), heir('h2')], confirmations: ['h1', 'h2'] });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });

  it('REFUSES when no heir has confirmed at all', async () => {
    const { svc, updates } = makeService({ heirs: [heir('h1')], confirmations: [] });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/have not confirmed/i);
    expect(released(updates)).toBe(false);
  });

  // The refusal is shown to an ADMIN, who has no business reading a private will's roster
  // out of an error string. A count, never names or contact details.
  it('names nobody in the refusal', async () => {
    const { svc } = makeService({
      heirs: [heir('h1', { email: 'aisha.private@example.com' })],
      confirmations: [],
    });
    const err = (await svc.release('c1', 'admin1').catch((e) => e)) as Error;
    expect(err.message).not.toContain('aisha');
    expect(err.message).not.toContain('example.com');
    expect(err.message).not.toContain('h1');
    expect(err.message).toMatch(/1 of 1 heir/);
  });
});

/**
 * Heirs who share one sign-in address are ONE party, because the portal can only ask them
 * once.
 *
 * The portal signs in by email and resolveParty binds the session to the FIRST roster row
 * carrying that address. So a testator who records two adult sons on the family email —
 * ordinary, and nothing stops it at seal — made the second row permanently unconfirmable:
 * whichever brother signs in is bound to the same row, and /portal/claim even tells the
 * second one `myConfirmationPending: false`. The gate then blocked release forever, and only
 * a trustee override could clear it.
 *
 * Requiring one answer per ROW required something the system cannot solicit — the same
 * reasoning that already exempts an heir with no contact details at all.
 */
describe('heirs sharing one address cannot deadlock the gate', () => {
  const shared = (id: string, over: any = {}) => heir(id, { email: 'family@x.com', phone: null, ...over });

  it('RELEASES once the shared mailbox has confirmed, whichever row was bound', async () => {
    const { svc, updates } = makeService({
      heirs: [shared('omar'), shared('khalid')],
      confirmations: ['omar'], // resolveParty bound both brothers to the first row
    });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });

  it('still waits when the shared mailbox has said nothing', async () => {
    const { svc, updates } = makeService({ heirs: [shared('omar'), shared('khalid')], confirmations: [] });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/1 of 1 heir/);
    expect(released(updates)).toBe(false);
  });

  it('counts a shared mailbox as ONE party alongside a separate heir', async () => {
    const { svc } = makeService({
      heirs: [shared('omar'), shared('khalid'), heir('aisha')],
      confirmations: ['omar'],
    });
    // Two parties — the mailbox and Aisha — and only Aisha is outstanding.
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/1 of 2 heir/);
  });

  it('keeps PHONE-ONLY heirs distinct — they share no sign-in address to collide on', async () => {
    const { svc } = makeService({
      heirs: [heir('h1', { email: null }), heir('h2', { email: null })],
      confirmations: ['h1'],
    });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/1 of 2 heir/);
  });

  it('matches addresses case- and whitespace-insensitively, as the portal does', async () => {
    const { svc, updates } = makeService({
      heirs: [
        heir('omar', { email: 'Family@X.com', phone: null }),
        heir('khalid', { email: '  family@x.com ', phone: null }),
      ],
      confirmations: ['omar'],
    });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });
});

describe('the trustee override unblocks release', () => {
  it('RELEASES with the override set, even with every heir outstanding', async () => {
    const { svc, updates } = makeService({
      heirs: [heir('h1'), heir('h2'), heir('h3')],
      confirmations: [],
      overrideAt: new Date(),
    });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });
});

describe('the gate is VACUOUS when nobody is reachable', () => {
  // The failure mode this prevents: a will whose heirs were entered without contact details
  // would be permanently unreleasable, and the 90-day purge would then erase the estate
  // that could never be handed over. A gate that cannot be satisfied is not a safeguard.
  it('RELEASES when the will has no heir roster at all', async () => {
    const { svc, updates } = makeService({ heirs: [] });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });

  it('RELEASES when every heir has neither a phone nor an email', async () => {
    const { svc, updates } = makeService({
      heirs: [heir('h1', { phone: null, email: null }), heir('h2', { phone: null, email: null })],
      confirmations: [],
    });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });

  it('RELEASES when every heir is a minor', async () => {
    const { svc, updates } = makeService({
      heirs: [heir('h1', { isMinor: true }), heir('h2', { isMinor: true })],
      confirmations: [],
    });
    await svc.release('c1', 'admin1');
    expect(released(updates)).toBe(true);
  });

  // Mixed roster: the unreachable ones drop out, and the ONE reachable heir still gates.
  it('still waits on the one reachable heir among unreachable ones', async () => {
    const { svc, updates } = makeService({
      heirs: [heir('h1', { isMinor: true }), heir('h2', { phone: null, email: null }), heir('h3')],
      confirmations: [],
    });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/1 of 1 heir/);
    expect(released(updates)).toBe(false);

    const ok = makeService({
      heirs: [heir('h1', { isMinor: true }), heir('h2', { phone: null, email: null }), heir('h3')],
      confirmations: ['h3'],
    });
    await ok.svc.release('c1', 'admin1');
    expect(released(ok.updates)).toBe(true);
  });

  // A phone-only heir IS reachable by the gate's definition. Recorded here as the shape it
  // is, not as an accident: the portal signs in by email, so such an heir cannot confirm and
  // only a trustee override clears them. The product requires an email on every heir before
  // a will can seal, so this is a legacy roster, not the designed one.
  it('counts a phone-only heir as reachable (documented limit — override is their only clearance)', async () => {
    const { svc } = makeService({ heirs: [heir('h1', { email: null })], confirmations: [] });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/have not confirmed/i);

    const overridden = makeService({ heirs: [heir('h1', { email: null })], overrideAt: new Date() });
    await overridden.svc.release('c1', 'admin1');
    expect(released(overridden.updates)).toBe(true);
  });
});

describe('the heir gate runs AFTER the existing anti-fraud gates, not instead of them', () => {
  it('still refuses an unsealed will even with every heir confirmed', async () => {
    const { svc } = makeService({ heirs: [heir('h1')], confirmations: ['h1'] });
    // Reach in and unseal: the heir gate must not have become the only thing checked.
    const prisma: any = (svc as any).prisma;
    const claim = await prisma.deathClaim.findUnique();
    claim.will.status = 'DRAFT';
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/never sealed/i);
  });

  it('still refuses when no trustee has confirmed, even with every heir confirmed', async () => {
    const { svc } = makeService({ heirs: [heir('h1')], confirmations: ['h1'] });
    const prisma: any = (svc as any).prisma;
    const claim = await prisma.deathClaim.findUnique();
    claim.will.trustees = [{ status: 'PENDING' }];
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/trustee must confirm/i);
  });
});
