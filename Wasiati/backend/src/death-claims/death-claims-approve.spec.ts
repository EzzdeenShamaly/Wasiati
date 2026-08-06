import { NotFoundException } from '@nestjs/common';
import { DeathClaimsService } from './death-claims.service';

/**
 * The review -> approve half of the claim path. `release` is guarded in
 * death-claims-release.spec.ts, but it only holds if approve does its half:
 * release REFUSES unless `status === 'APPROVED'` AND `safetyCheckSentAt` is set,
 * so those two writes are a contract between the methods, not incidental fields.
 * Nothing covered these two methods before — they are what moves a claim toward
 * handing over a dead person's estate.
 *
 * Both state guards are the atomic `updateMany({ where: { status: { in: [...] } } })`
 * kind, so `updateMany` below EVALUATES the where clause against the claim rather
 * than returning a canned count. Drop the status filter from the service's where and
 * these tests fail — which is the whole point of asserting a guard that lives in a
 * query rather than in an `if`.
 */
const HOUR = 60 * 60 * 1000;

function makeService(
  opts: { claim?: any; config?: Record<string, string>; smsThrows?: boolean; otpThrows?: boolean } = {},
) {
  const updates: any[] = [];
  const otpIssued: { phone: string; purpose: string; userId?: string }[] = [];
  const smsSent: { phone: string; body: string }[] = [];

  const prisma: any = {
    deathClaim: {
      findUnique: async () => opts.claim ?? null,
      findUniqueOrThrow: async () => opts.claim,
      update: async ({ data }: any) => {
        updates.push(data);
        return { id: 'c1', ...data };
      },
      updateMany: async ({ where, data }: any) => {
        const allowed: string[] | undefined = where?.status?.in;
        if (allowed && !allowed.includes(opts.claim?.status)) return { count: 0 };
        updates.push(data);
        return { count: 1 };
      },
    },
    user: { update: async () => ({}), findMany: async () => [] },
    will: { findUnique: async () => ({ id: 'w1' }) },
  };
  const notifications: any = {
    sendEmail: async () => undefined,
    sendSms: async (phone: string, body: string) => {
      if (opts.smsThrows) throw new Error('sms provider down');
      smsSent.push({ phone, body });
    },
  };
  const otp: any = {
    verify: async () => true,
    issue: async (phone: string, purpose: string, userId?: string) => {
      // OtpService.issue THROWS a ServiceUnavailableException when the transport reports
      // non-delivery — it is not a best-effort void call, and this fake has to be able to
      // behave like the real one or the guard around it cannot be tested.
      if (opts.otpThrows) throw new Error('We could not send your verification code right now.');
      otpIssued.push({ phone, purpose, userId });
      return '123456';
    },
  };
  const retention: any = { purgeDeadline: () => new Date(), sendReleaseNotice: async () => undefined };
  const config: any = { get: (k: string) => opts.config?.[k] };
  const redis: any = { incrWithTtl: async () => 1 };
  return {
    svc: new DeathClaimsService(prisma, notifications, otp, retention, config, redis, {} as any),
    updates,
    otpIssued,
    smsSent,
  };
}

const claimIn = (status: string, over: any = {}) => ({
  id: 'c1',
  status,
  submittedByPhone: '+15551111111',
  will: {
    id: 'w1',
    ownerId: 'owner-1',
    status: 'SEALED',
    owner: { email: 'owner@x.com', phone: '+15559999999' },
    trustees: [{ status: 'CONFIRMED' }],
    // No heirs on the roster, so the heir-confirmation gate is VACUOUS and these tests go
    // on exercising exactly what they were written for — the approve/release seam. The
    // gate itself is driven in death-claims-heir-gate.spec.ts.
    heirContacts: [],
  },
  ...over,
});

describe('DeathClaimsService.markUnderReview — source-state guard', () => {
  it('moves a SUBMITTED claim into review and attributes the admin', async () => {
    const { svc, updates } = makeService({ claim: claimIn('SUBMITTED') });
    await svc.markUnderReview('c1', 'admin1');
    expect(updates).toContainEqual({ status: 'UNDER_REVIEW', reviewedBy: 'admin1' });
  });

  it('is idempotent — an UNDER_REVIEW claim may be re-marked', async () => {
    const { svc, updates } = makeService({ claim: claimIn('UNDER_REVIEW') });
    await svc.markUnderReview('c1', 'admin1');
    expect(updates).toHaveLength(1);
  });

  // A decided claim must not be draggable back into the queue and re-decided.
  for (const status of ['REJECTED', 'RELEASED', 'APPROVED']) {
    it(`REFUSES to drag a ${status} claim back into review`, async () => {
      const { svc, updates } = makeService({ claim: claimIn(status) });
      await expect(svc.markUnderReview('c1', 'admin1')).rejects.toThrow(/already decided/i);
      expect(updates).toHaveLength(0); // nothing was written
    });
  }
});

describe('DeathClaimsService.approveAndSendSafetyCheck', () => {
  // The contract release depends on. If either write is renamed or dropped, release
  // silently refuses forever (or, worse, stops requiring the anti-fraud delay).
  it('writes exactly what release gates on: APPROVED + a safetyCheckSentAt date', async () => {
    const { svc, updates } = makeService({ claim: claimIn('SUBMITTED') });
    await svc.approveAndSendSafetyCheck('c1', 'admin1');
    const written = updates.find((u) => u.status === 'APPROVED');
    expect(written).toBeDefined();
    expect(written.safetyCheckSentAt).toBeInstanceOf(Date);
    expect(written.reviewedBy).toBe('admin1');
    expect(written.reviewedAt).toBeInstanceOf(Date);
  });

  it('approves from UNDER_REVIEW too', async () => {
    const { svc, updates } = makeService({ claim: claimIn('UNDER_REVIEW') });
    await svc.approveAndSendSafetyCheck('c1', 'admin1');
    expect(updates.some((u) => u.status === 'APPROVED')).toBe(true);
  });

  // The fraud ping goes to the DECEASED's own phone — the whole signal is "if this
  // number answers, the claim is a lie". Sending it to the claimant instead would
  // ping the very person who filed the claim and destroy the check.
  it('pings the OWNER\'s phone, not the claimant\'s, with the safety-check purpose', async () => {
    const { svc, otpIssued } = makeService({ claim: claimIn('SUBMITTED') });
    await svc.approveAndSendSafetyCheck('c1', 'admin1');
    expect(otpIssued).toHaveLength(1);
    expect(otpIssued[0]).toEqual({
      phone: '+15559999999', // owner
      purpose: 'death_claim_safety_check',
      userId: 'owner-1',
    });
    expect(otpIssued[0].phone).not.toBe('+15551111111'); // never the submitter
  });

  // Everything after the APPROVED write has already committed, so nothing after it may
  // throw. The 72h window is the single delay standing between a forged certificate and a
  // released estate, and it starts ticking at that write — an exception thrown afterwards
  // does not stop the clock, it only stops anyone from being told the clock is running.
  describe('when the safety-check ping cannot be delivered', () => {
    it('still approves, still tells the claimant, and reports that the ping failed', async () => {
      const { svc, updates, smsSent } = makeService({ claim: claimIn('SUBMITTED'), otpThrows: true });

      const res: any = await svc.approveAndSendSafetyCheck('c1', 'admin1');

      // The transition stands — it is already in the database either way.
      expect(updates.some((u) => u.status === 'APPROVED')).toBe(true);
      // The claimant is told. Before the guard, the throw skipped this entirely: the
      // window ran for three days while the person who filed the claim heard nothing and
      // the admin believed the approval had failed.
      expect(smsSent).toHaveLength(1);
      expect(smsSent[0].phone).toBe('+15551111111');
      // And the caller can SAY the ping failed, rather than the failure living only in a log.
      expect(res.safetyPingSent).toBe(false);
    });

    it('reports the ping as sent on the happy path, so the flag means something', async () => {
      const { svc } = makeService({ claim: claimIn('SUBMITTED') });
      const res: any = await svc.approveAndSendSafetyCheck('c1', 'admin1');
      expect(res.safetyPingSent).toBe(true);
    });
  });

  for (const status of ['REJECTED', 'RELEASED']) {
    it(`REFUSES to approve a ${status} claim`, async () => {
      const { svc, updates } = makeService({ claim: claimIn(status) });
      await expect(svc.approveAndSendSafetyCheck('c1', 'admin1')).rejects.toThrow(/cannot be approved/i);
      expect(updates).toHaveLength(0);
    });
  }

  // Re-approving would stamp a fresh safetyCheckSentAt and silently restart the 72h
  // anti-fraud window — or, if it were ever allowed post-release, re-open a closed case.
  it('REFUSES to re-approve an already APPROVED claim (would restart the safety window)', async () => {
    const { svc, updates, otpIssued } = makeService({ claim: claimIn('APPROVED') });
    await expect(svc.approveAndSendSafetyCheck('c1', 'admin1')).rejects.toThrow(/cannot be approved/i);
    expect(updates).toHaveLength(0);
    expect(otpIssued).toHaveLength(0);
  });

  it('404s an unknown claim', async () => {
    const { svc } = makeService({ claim: null });
    await expect(svc.approveAndSendSafetyCheck('missing', 'admin1')).rejects.toThrow(NotFoundException);
  });

  // DECIDED — DECISIONS §15. A phoneless owner still approves, and safetyCheckSentAt is
  // stamped even though nothing was pinged. That is deliberate, not an oversight: the
  // stamp starts the 72h cooling-off delay, and it never recorded that a liveness probe
  // succeeded, because no such probe exists for ANY owner — nothing in the backend
  // consumes a response to the ping. Phoneless owners are the common case (phone is
  // optional at registration and cannot be added afterwards), so refusing here would
  // strand their claims to enforce a check that does nothing even when it passes.
  // Release still requires human review, the delay, a SEALED will and a CONFIRMED trustee.
  it('approves an owner with no phone — the stamp starts the delay, it is not proof of life', async () => {
    const claim = claimIn('SUBMITTED');
    claim.will.owner.phone = null;
    const { svc, updates, otpIssued } = makeService({ claim });
    await svc.approveAndSendSafetyCheck('c1', 'admin1');
    expect(otpIssued).toHaveLength(0); // nothing to ping, and nothing would consume it
    const written = updates.find((u) => u.status === 'APPROVED');
    expect(written.safetyCheckSentAt).toBeInstanceOf(Date); // the delay still starts
  });

  // notifySubmitter is explicitly best-effort: an SMS outage must never roll back or
  // block an admin's decision on the claim itself.
  it('approves even when notifying the claimant throws', async () => {
    const { svc, updates } = makeService({ claim: claimIn('SUBMITTED'), smsThrows: true });
    await expect(svc.approveAndSendSafetyCheck('c1', 'admin1')).resolves.toBeDefined();
    expect(updates.some((u) => u.status === 'APPROVED')).toBe(true);
  });

  it('tells the claimant their claim was approved', async () => {
    const { svc, smsSent } = makeService({ claim: claimIn('SUBMITTED') });
    await svc.approveAndSendSafetyCheck('c1', 'admin1');
    expect(smsSent).toHaveLength(1);
    expect(smsSent[0].phone).toBe('+15551111111'); // the submitter
    expect(smsSent[0].body).toMatch(/approved/i);
  });
});

/**
 * THE RACE. approve used to read the claim, check `status` in an `if`, and then write —
 * so two admins clicking Approve at the same moment BOTH read SUBMITTED, both passed the
 * check, and both wrote. The second write re-stamped `safetyCheckSentAt`, silently
 * restarting the 72h anti-fraud window that is the only delay between a forged
 * certificate and a released estate; it also fired a SECOND safety-check SMS at the
 * deceased's own number.
 *
 * The fix is the same atomic `updateMany` guard `markUnderReview` and `reject` already
 * used — the status filter lives in the WHERE clause, so the database picks one winner.
 *
 * The harness below models the real concurrency: a single shared row whose status is read
 * INSIDE updateMany at call time, so the second caller sees what the first one wrote.
 */
describe('DeathClaimsService.approveAndSendSafetyCheck — concurrent approves', () => {
  function racingService() {
    const row = { status: 'SUBMITTED' };
    const writes: any[] = [];
    const otpIssued: any[] = [];

    const claim = {
      id: 'c1',
      submittedByPhone: '+15551111111',
      get status() {
        return row.status;
      },
      will: {
        id: 'w1',
        ownerId: 'owner-1',
        status: 'SEALED',
        owner: { email: 'o@x.com', phone: '+15559999999' },
        heirContacts: [],
      },
    };

    const prisma: any = {
      deathClaim: {
        findUnique: async () => claim,
        updateMany: async ({ where, data }: any) => {
          const allowed: string[] = where?.status?.in ?? [];
          // Read-and-write against the shared row, the way a conditional UPDATE does.
          if (!allowed.includes(row.status)) return { count: 0 };
          row.status = data.status;
          writes.push(data);
          return { count: 1 };
        },
      },
      user: { findMany: async () => [] },
    };
    const notifications: any = { sendEmail: async () => undefined, sendSms: async () => undefined };
    const otp: any = {
      issue: async (phone: string, purpose: string) => {
        otpIssued.push({ phone, purpose });
        return '123456';
      },
    };
    const svc = new DeathClaimsService(
      prisma,
      notifications,
      otp,
      {} as any,
      { get: () => undefined } as any,
      { incrWithTtl: async () => 1 } as any,
      {} as any,
    );
    return { svc, writes, otpIssued };
  }

  it('lets exactly ONE of two concurrent approves win', async () => {
    const { svc, writes } = racingService();
    const results = await Promise.allSettled([
      svc.approveAndSendSafetyCheck('c1', 'admin1'),
      svc.approveAndSendSafetyCheck('c1', 'admin2'),
    ]);

    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(results.filter((r) => r.status === 'rejected')).toHaveLength(1);
    // One APPROVED write only — a second would re-stamp safetyCheckSentAt and restart
    // the 72h window from zero.
    expect(writes.filter((w) => w.status === 'APPROVED')).toHaveLength(1);
  });

  // The ping goes to the DECEASED's phone. A losing caller must not fire a second one at
  // a bereaved family — which is exactly what happens when the OTP is sent BEFORE the
  // state transition rather than after it.
  it('sends the safety-check SMS exactly once, not once per caller', async () => {
    const { svc, otpIssued } = racingService();
    await Promise.allSettled([
      svc.approveAndSendSafetyCheck('c1', 'admin1'),
      svc.approveAndSendSafetyCheck('c1', 'admin2'),
    ]);

    expect(otpIssued).toHaveLength(1);
    expect(otpIssued[0]).toEqual({ phone: '+15559999999', purpose: 'death_claim_safety_check' });
  });
});

describe('approve -> release seam', () => {
  // The two methods are only ever tested apart. This walks the handoff: approve's own
  // written record, aged past the window, must be exactly what release accepts.
  it('a claim approved by approveAndSendSafetyCheck is releasable once the window elapses', async () => {
    const a = makeService({ claim: claimIn('SUBMITTED') });
    await a.svc.approveAndSendSafetyCheck('c1', 'admin1');
    const written = a.updates.find((u) => u.status === 'APPROVED');

    // Age the safety-check stamp past the default 72h window; everything else is the
    // record approve actually produced.
    const aged = claimIn(written.status, {
      safetyCheckSentAt: new Date(written.safetyCheckSentAt.getTime() - 100 * HOUR),
      reviewedBy: written.reviewedBy,
    });
    const r = makeService({ claim: aged, config: {} });
    await expect(r.svc.release('c1', 'admin2')).resolves.toEqual({ released: true });
  });
});
