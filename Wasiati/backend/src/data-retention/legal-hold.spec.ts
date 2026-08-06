import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DataRetentionService } from './data-retention.service';

/**
 * The purge is an automated, irreversible destruction job aimed at the one document a
 * family may end up in court over. A contested will, a probate dispute or any
 * preservation obligation is an ordinary event in this domain — and until this existed,
 * nothing could stop the job: it would destroy the disputed instrument on schedule and
 * write a tombstone recording that we meant to. That is the shape of spoliation FRCP
 * 37(e) exists for.
 *
 * A hold outranks scheduledPurgeAt, lasts indefinitely, and lifts only by an explicit
 * admin action.
 */
function harness(user: any) {
  const updates: any[] = [];
  const destroyed: string[] = [];
  const tx: any = new Proxy(
    {},
    {
      get: () =>
        new Proxy(
          {},
          { get: (_m, op: string) => async () => (op === 'deleteMany' || op === 'updateMany' ? { count: 0 } : {}) },
        ),
    },
  );
  const prisma: any = {
    user: {
      findUnique: async () => user,
      findMany: async ({ where }: any) => {
        // Mirrors the real nightly queries, both of which exclude held estates.
        const held = user?.legalHoldAt != null;
        if (where.legalHoldAt === null && held) return [];
        return [
          {
            id: 'u1',
            email: 'owner@x.com',
            scheduledPurgeAt: new Date(Date.now() + 5 * 86_400_000),
            retentionRemindersSent: [],
          },
        ];
      },
      update: async ({ data }: any) => {
        updates.push(data);
        Object.assign(user, data);
        return user;
      },
      delete: async () => ({}),
    },
    will: { findMany: async () => [] },
    vault: { findUnique: async () => null },
    fileObject: { findMany: async () => [] },
    // The purge transaction touches ~20 models; stub them all generically.
    $transaction: async (fn: any) => fn(tx),
  };
  const storage: any = {
    configured: true,
    purgePrefix: async (p: string) => {
      destroyed.push(p);
      return { method: 'versions', objectsDeleted: 0, versionsDeleted: 0, deleteMarkersDeleted: 0, verifiedEmpty: true };
    },
  };
  const identity: any = {
    redactPersonalData: async () => {
      destroyed.push('identity');
      return { provider: 'Stripe Identity', supported: true, sessionsFound: 0, redactionRequested: 0, alreadyRedacted: 0 };
    },
  };
  const svc = new DataRetentionService(prisma, { get: () => undefined } as any, {} as any, storage, identity);
  return { svc, updates, destroyed };
}

const held = () => ({ id: 'u1', legalHoldAt: new Date('2026-07-01'), legalHoldReason: 'will contested in probate' });
const free = () => ({ id: 'u1', legalHoldAt: null, legalHoldReason: null, idVerificationProvider: null });

describe('a held estate cannot be purged', () => {
  it('REFUSES the admin one-click purge, and destroys nothing on the way to refusing', async () => {
    const h = harness(held());
    await expect(h.svc.purgeUser('u1')).rejects.toBeInstanceOf(ConflictException);
    // The check must precede the IRREVERSIBLE steps — a refusal that has already wiped
    // the bucket is not a refusal. This is the whole ordering argument.
    expect(h.destroyed).toEqual([]);
  });

  it('says WHY, so the operator can see what is preserving it', async () => {
    const h = harness(held());
    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/will contested in probate/);
  });

  it('is skipped by the nightly sweep rather than failing loudly every night', async () => {
    const h = harness(held());
    await expect(h.svc.runDailyPurge()).resolves.toBeUndefined();
    expect(h.destroyed).toEqual([]);
  });

  it('stops counting down to a deadline that will never arrive', async () => {
    // The reminders say "you have N days to retrieve everything". Under a hold there is no
    // deadline, so that is simply untrue — and sending burns the milestone flag, meaning the
    // REAL countdown could never be announced if the hold were later released.
    const h = harness(held());
    await expect(h.svc.sendDueReminders()).resolves.toEqual({ remindedAccounts: 0 });
    expect(h.updates).toEqual([]);

    // Positive control: the same account, unheld, is reminded.
    const g = harness(free());
    await expect(g.svc.sendDueReminders()).resolves.toEqual({ remindedAccounts: 1 });
  });

  it('purges normally once the hold is lifted', async () => {
    const user = held();
    const h = harness(user);
    await h.svc.releaseLegalHold('u1', 'admin-1');
    await expect(h.svc.purgeUser('u1')).resolves.toBeDefined();
    expect(h.destroyed.length).toBeGreaterThan(0);
  });
});

describe('placing and lifting a hold', () => {
  it('records when, why and by whom', async () => {
    const h = harness(free());
    await expect(h.svc.placeLegalHold('u1', 'admin-1', 'Estate contested — Smith v. Smith, filed 2026-07-02')).resolves
      .toEqual({ userId: 'u1', held: true });
    expect(h.updates[0].legalHoldBy).toBe('admin-1');
    expect(h.updates[0].legalHoldReason).toContain('Smith v. Smith');
    expect(h.updates[0].legalHoldAt).toBeInstanceOf(Date);
  });

  it('demands a real reason — "why was this preserved for three years?" gets asked later', async () => {
    const h = harness(free());
    await expect(h.svc.placeLegalHold('u1', 'admin-1', 'x')).rejects.toBeInstanceOf(BadRequestException);
    await expect(h.svc.placeLegalHold('u1', 'admin-1', '   ')).rejects.toBeInstanceOf(BadRequestException);
    expect(h.updates).toHaveLength(0);
  });

  it('will not double-place or release what is not held', async () => {
    const h = harness(held());
    await expect(h.svc.placeLegalHold('u1', 'admin-1', 'another reason entirely')).rejects.toBeInstanceOf(
      ConflictException,
    );
    const g = harness(free());
    await expect(g.svc.releaseLegalHold('u1', 'admin-1')).rejects.toBeInstanceOf(ConflictException);
  });

  it('clears every field on release, so nothing stale blocks a later purge', async () => {
    const h = harness(held());
    await expect(h.svc.releaseLegalHold('u1', 'admin-1')).resolves.toEqual({ userId: 'u1', held: false });
    expect(h.updates[0]).toEqual({ legalHoldAt: null, legalHoldReason: null, legalHoldBy: null });
  });

  it('404s for an unknown user rather than silently doing nothing', async () => {
    const h = harness(null);
    await expect(h.svc.placeLegalHold('nope', 'admin-1', 'a perfectly good reason')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });
});
