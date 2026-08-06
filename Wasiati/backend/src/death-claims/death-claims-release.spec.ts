import { NotFoundException } from '@nestjs/common';
import { DeathClaimsService } from './death-claims.service';

/**
 * Release hands the will to the heirs and starts an irreversible purge clock, so the
 * anti-fraud gates around it are load-bearing:
 *   1. the safety-check window must elapse (a living account-holder's chance to stop it);
 *   2. the will must be SEALED and a trustee CONFIRMED.
 * And the certificate host guard must reject an off-host (SSRF) URL at submit time.
 */
const HOUR = 60 * 60 * 1000;

function makeService(
  opts: {
    claim?: any;
    config?: Record<string, string>;
    /**
     * Simulates the world moving BETWEEN release()'s read and its write — another admin
     * rejecting the claim, or a second release winning the race. findUnique still answers
     * APPROVED (that read already happened), but the conditional write now matches nothing.
     */
    lostRace?: boolean;
  } = {},
) {
  const updates: any[] = [];
  const handOffs: string[] = [];
  const prisma: any = {
    deathClaim: {
      findUnique: async () => opts.claim ?? null,
      // Honours `where.status`, deliberately. A double that ignored it would keep passing
      // if the atomic status guard in release() were deleted — which is the whole thing
      // these tests exist to hold in place.
      updateMany: async ({ where, data }: any) => {
        if (opts.lostRace) return { count: 0 };
        if (where?.status && where.status !== opts.claim?.status) return { count: 0 };
        updates.push(data);
        return { count: 1 };
      },
      update: async ({ data }: any) => {
        updates.push(data);
        return { id: 'c1', ...data };
      },
    },
    user: { update: async () => ({}), findMany: async () => [] },
    will: { findUnique: async () => ({ id: 'w1' }) },
  };
  const notifications: any = { sendEmail: async () => undefined, sendSms: async () => undefined };
  const otp: any = { verify: async () => true };
  const retention: any = {
    purgeDeadline: () => new Date(),
    sendReleaseNotice: async (ownerId: string) => {
      handOffs.push(ownerId);
    },
  };
  const config: any = { get: (k: string) => opts.config?.[k] };
  const redis: any = { incrWithTtl: async () => 1 };
  return { svc: new DeathClaimsService(prisma, notifications, otp, retention, config, redis, {} as any), updates, handOffs };
}

const approvedClaim = (over: any = {}) => ({
  id: 'c1',
  status: 'APPROVED',
  safetyCheckSentAt: new Date(Date.now() - 100 * HOUR), // window long elapsed
  will: {
    id: 'w1',
    ownerId: 'owner-1',
    status: 'SEALED',
    owner: { email: 'owner@x.com' },
    trustees: [{ status: 'CONFIRMED' }],
    // Empty roster => the heir-confirmation gate is VACUOUS, so these tests keep driving
    // the anti-fraud gates they were written for. The heir gate has its own suite,
    // death-claims-heir-gate.spec.ts.
    heirContacts: [],
  },
  ...over,
});

describe('DeathClaimsService.release — anti-fraud gates', () => {
  it('releases once the window has elapsed and all conditions hold', async () => {
    const { svc, updates } = makeService({ claim: approvedClaim(), config: {} });
    await svc.release('c1', 'admin1');
    expect(updates.some((u) => u.status === 'RELEASED')).toBe(true);
  });

  // The gap between "read the claim and see APPROVED" and "write RELEASED" is small, and
  // for most endpoints that would be an acceptable risk. Not here: everything on the far
  // side of that write is irreversible — the estate is disclosed and the 90-day purge
  // clock starts — so the status has to be re-checked BY the write, not before it.
  describe('the read-to-write gap', () => {
    it('does NOT release a claim that was REJECTED while this release was being prepared', async () => {
      // The scenario that makes this urgent: admin B rejects the claim, perhaps having
      // just recognised the certificate as forged. That transition is atomic and wins.
      // An unconditional `update` by id would then write RELEASED straight over it, and
      // the fraud is handed the estate by the very action taken to stop it.
      const { svc, updates, handOffs } = makeService({ claim: approvedClaim(), lostRace: true, config: {} });

      await expect(svc.release('c1', 'admin1')).rejects.toThrow(/no longer approved/i);

      expect(updates.some((u) => u.status === 'RELEASED')).toBe(false);
      // And nothing downstream ran: no heir was emailed, no purge clock started.
      expect(handOffs).toEqual([]);
    });

    it('lets only ONE of two racing releases perform the hand-off', async () => {
      // Both callers pass every precondition; only one write can match. The loser must not
      // re-send release notices — being told twice that a parent's will has been released
      // is not a cosmetic duplicate.
      const winner = makeService({ claim: approvedClaim(), config: {} });
      await winner.svc.release('c1', 'admin1');
      expect(winner.handOffs).toEqual(['owner-1']);

      const loser = makeService({ claim: approvedClaim(), lostRace: true, config: {} });
      await expect(loser.svc.release('c1', 'admin2')).rejects.toThrow(/no longer approved/i);
      expect(loser.handOffs).toEqual([]);
    });
  });

  it('REFUSES to release before the safety-check window elapses', async () => {
    const claim = approvedClaim({ safetyCheckSentAt: new Date(Date.now() - 1 * HOUR) }); // only 1h ago
    const { svc } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/window has not elapsed/i);
  });

  it('honours a custom window from DEATH_CLAIM_SAFETY_WINDOW_HOURS', async () => {
    const claim = approvedClaim({ safetyCheckSentAt: new Date(Date.now() - 5 * HOUR) }); // 5h ago
    // With a 72h default this would pass 5h? No — 5h < 72h fails. Set window to 4h so it passes.
    const { svc, updates } = makeService({ claim, config: { DEATH_CLAIM_SAFETY_WINDOW_HOURS: '4' } });
    await svc.release('c1', 'admin1');
    expect(updates.some((u) => u.status === 'RELEASED')).toBe(true);
  });

  it('REFUSES release when the safety-check was never sent', async () => {
    const claim = approvedClaim({ safetyCheckSentAt: null });
    const { svc } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/safety-check has not been sent/i);
  });

  it('REFUSES release of a claim that is not APPROVED', async () => {
    const claim = approvedClaim({ status: 'SUBMITTED' });
    const { svc } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/approved before release/i);
  });

  it('REFUSES release when no trustee has confirmed', async () => {
    const claim = approvedClaim();
    claim.will.trustees = [{ status: 'PENDING' }];
    const { svc } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/trustee must confirm/i);
  });

  // Release hands the estate over, so "no trustee row at all" must fail exactly like
  // an unconfirmed one — an empty roster is the absence of confirmation, not a pass.
  it('REFUSES release when the will has no trustee at all', async () => {
    const claim = approvedClaim();
    claim.will.trustees = [];
    const { svc, updates } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/trustee must confirm/i);
    expect(updates).toHaveLength(0); // nothing was released
  });

  it('releases on ANY one confirmed trustee among several rows', async () => {
    const claim = approvedClaim();
    claim.will.trustees = [{ status: 'PENDING' }, { status: 'CONFIRMED' }];
    const { svc, updates } = makeService({ claim, config: {} });
    await svc.release('c1', 'admin1');
    expect(updates.some((u) => u.status === 'RELEASED')).toBe(true);
  });

  it('REFUSES release of an unsealed will', async () => {
    const claim = approvedClaim();
    claim.will.status = 'DRAFT';
    const { svc } = makeService({ claim, config: {} });
    await expect(svc.release('c1', 'admin1')).rejects.toThrow(/never sealed/i);
  });

  it('404s an unknown claim', async () => {
    const { svc } = makeService({ claim: null, config: {} });
    await expect(svc.release('missing', 'admin1')).rejects.toThrow(NotFoundException);
  });
});

/**
 * REPLACES the old "certificate host guard (SSRF)" block, which drove
 * `assertCertificateHost` — a runtime allow-list checking that a CALLER-SUPPLIED
 * `certificateFileUrl` sat on our storage host. Both the field and the allow-list are
 * gone: submit now takes a `certificateFileId`, and the URL is DERIVED from the file
 * row the server looked up. There is no longer a client-controlled URL for a reviewer
 * to be lured into fetching, so the defence is structural rather than a check that
 * could be bypassed by a parser disagreement or forgotten on a new path.
 *
 * These tests pin that: the stored URL must be server-derived, and the file must be a
 * real, scanned death certificate.
 */
describe('DeathClaimsService.submitClaim — the certificate cannot be an attacker URL', () => {
  const PRINCIPAL: any = {
    tokenId: 'tok-1',
    willId: 'w1',
    claimId: null,
    role: 'WITNESS',
    scope: 'CLAIM_SUBMIT',
    subjectPhone: '+15559990000',
    subjectEmail: null,
    heirContactId: null,
  };

  function submitService(file: any, config: Record<string, string> = {}) {
    const created: any[] = [];
    const prisma: any = {
      // ownerId is REAL here, not omitted. Without it both sides of the ownership check
      // are undefined, `undefined !== undefined` is false, and every one of these tests
      // would pass with the check deleted.
      will: { findUnique: async () => ({ id: 'w1', ownerId: 'owner-1', owner: { email: 'o@x.com' } }) },
      fileObject: { findUnique: async () => file },
      claimAccessToken: {
        updateMany: async () => ({ count: 1 }),
        update: async () => ({}),
        // submitClaim reads subjectPhone off the token ROW: it is the number the
        // invitation was delivered to, and the only phone in this flow that came off the
        // will's roster rather than out of a form.
        findUnique: async () => ({ subjectPhone: '+15559990000' }),
      },
      deathClaim: {
        create: async ({ data }: any) => {
          created.push(data);
          return { id: 'c1', ...data };
        },
      },
      user: { findMany: async () => [] },
    };
    prisma.$transaction = async (fn: any) => fn(prisma);
    const notifications: any = { sendEmail: async () => undefined, sendSms: async () => undefined };
    const cfg: any = { get: (k: string) => config[k] };
    const redis: any = { incrWithTtl: async () => 1 };
    return {
      svc: new DeathClaimsService(prisma, notifications, {} as any, {} as any, cfg, redis, {} as any),
      created,
    };
  }

  // Claim uploads are attributed to the DECEASED OWNER, so a certificate for this estate
  // carries the will's ownerId.
  const cleanCert = { id: 'file-1', kind: 'death_certificate', scanStatus: 'CLEAN', userId: 'owner-1' };

  it('stores a URL derived from the file id, on OUR host — never anything the caller sent', async () => {
    const { svc, created } = submitService(cleanCert, { APP_BASE_URL: 'https://app.wasiati.com' });
    await svc.submitClaim(PRINCIPAL, 'Ali', 'file-1');
    expect(created[0].certificateFileUrl).toBe('https://app.wasiati.com/files/file-1/download');
  });

  it('REFUSES a file that is not a death certificate', async () => {
    const { svc } = submitService({ id: 'file-1', kind: 'id_document', scanStatus: 'CLEAN' });
    await expect(svc.submitClaim(PRINCIPAL, 'Ali', 'file-1')).rejects.toThrow(/death certificate/i);
  });

  it('REFUSES an unknown file id', async () => {
    const { svc } = submitService(null);
    await expect(svc.submitClaim(PRINCIPAL, 'Ali', 'nope')).rejects.toThrow(/death certificate/i);
  });

  // The id is not a secret: the upload endpoint hands it back to whoever uploaded it. So
  // anyone who has legitimately filed on ONE estate holds a valid, CLEAN, correctly-typed
  // death_certificate id — and could present that genuine document as the evidence for a
  // DIFFERENT estate. The reviewer would be looking at a real death certificate for the
  // wrong person. Kind and scan status cannot catch this; only ownership can.
  it('REFUSES a genuine certificate that belongs to a different estate', async () => {
    const { svc, created } = submitService({ ...cleanCert, userId: 'someone-elses-estate' });
    await expect(svc.submitClaim(PRINCIPAL, 'Ali', 'file-1')).rejects.toThrow(/death certificate/i);
    expect(created).toEqual([]); // and no claim was filed on the way to refusing
  });

  it('says the SAME thing for a foreign file as for a missing one, so it is not an oracle', async () => {
    // A distinct "that file is not yours" would confirm the id exists and is a clean death
    // certificate — turning the check into a probe over other estates' stored objects.
    const foreign = submitService({ ...cleanCert, userId: 'someone-elses-estate' });
    const missing = submitService(null);
    const msg = async (h: any) =>
      h.svc.submitClaim(PRINCIPAL, 'Ali', 'file-1').then(
        () => 'RESOLVED',
        (e: Error) => e.message,
      );
    expect(await msg(foreign)).toBe(await msg(missing));
  });

  // An admin reviewer opens this file by hand. Handing them an unscanned or infected
  // attachment turns the review queue into the delivery mechanism.
  it('REFUSES an INFECTED certificate', async () => {
    const { svc } = submitService({ ...cleanCert, scanStatus: 'INFECTED' });
    await expect(svc.submitClaim(PRINCIPAL, 'Ali', 'file-1')).rejects.toThrow(/security scan/i);
  });

  it('REFUSES a still-PENDING certificate rather than assuming it is safe', async () => {
    const { svc } = submitService({ ...cleanCert, scanStatus: 'PENDING' });
    await expect(svc.submitClaim(PRINCIPAL, 'Ali', 'file-1')).rejects.toThrow(/still being scanned/i);
  });
});

describe('DeathClaimsService.submitClaim — identity comes from the token', () => {
  const PRINCIPAL: any = {
    tokenId: 'tok-1',
    willId: 'will-from-token',
    claimId: null,
    role: 'HEIR',
    scope: 'CLAIM_SUBMIT',
    subjectPhone: '+966555123456',
    subjectEmail: 'heir@x.com',
    heirContactId: 'heir-1',
    };

  it('files against the token\'s will/phone/role, which the body has no way to influence', async () => {
    const created: any[] = [];
    const prisma: any = {
      will: { findUnique: async () => ({ id: 'will-from-token', ownerId: 'owner-1', owner: { email: 'o@x.com' } }) },
      fileObject: { findUnique: async () => ({ id: 'f1', kind: 'death_certificate', scanStatus: 'CLEAN', userId: 'owner-1' }) },
      claimAccessToken: {
        updateMany: async () => ({ count: 1 }),
        update: async () => ({}),
        findUnique: async () => ({ subjectPhone: '+966555123456' }),
      },
      deathClaim: {
        create: async ({ data }: any) => {
          created.push(data);
          return { id: 'c1', ...data };
        },
      },
      user: { findMany: async () => [] },
    };
    prisma.$transaction = async (fn: any) => fn(prisma);
    const svc = new DeathClaimsService(
      prisma,
      { sendEmail: async () => undefined } as any,
      {} as any,
      {} as any,
      { get: () => undefined } as any,
      { incrWithTtl: async () => 1 } as any,
      {} as any,
    );

    await svc.submitClaim(PRINCIPAL, 'Aisha', 'f1');
    expect(created[0].willId).toBe('will-from-token');
    expect(created[0].submittedByPhone).toBe('+966555123456');
    expect(created[0].submittedByRole).toBe('HEIR');
  });

  // Single-use. The link may sit in a shared family inbox; a second tap must not file
  // the same death twice, and the burn happens in the same transaction as the create.
  it('REFUSES a token that was already consumed', async () => {
    const prisma: any = {
      will: { findUnique: async () => ({ id: 'will-from-token', ownerId: 'owner-1', owner: { email: 'o@x.com' } }) },
      fileObject: { findUnique: async () => ({ id: 'f1', kind: 'death_certificate', scanStatus: 'CLEAN', userId: 'owner-1' }) },
      claimAccessToken: {
        updateMany: async () => ({ count: 0 }),
        update: async () => ({}),
        findUnique: async () => ({ subjectPhone: '+966555123456' }),
      },
      deathClaim: { create: jest.fn() },
      user: { findMany: async () => [] },
    };
    prisma.$transaction = async (fn: any) => fn(prisma);
    const svc = new DeathClaimsService(
      prisma,
      { sendEmail: async () => undefined } as any,
      {} as any,
      {} as any,
      { get: () => undefined } as any,
      { incrWithTtl: async () => 1 } as any,
      {} as any,
    );

    await expect(svc.submitClaim(PRINCIPAL, 'Aisha', 'f1')).rejects.toThrow(/already been used/i);
    expect(prisma.deathClaim.create).not.toHaveBeenCalled();
  });
});
