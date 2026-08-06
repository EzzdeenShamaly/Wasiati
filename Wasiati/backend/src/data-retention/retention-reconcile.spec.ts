import { Logger } from '@nestjs/common';
import { DataRetentionService } from './data-retention.service';

/**
 * Did the work we PROMISED actually happen?
 *
 * runDailyPurge catches a per-user failure, logs one line, and moves on. That is right for
 * the batch — one bad record must not halt the others — and wrong for the estate, because
 * nothing escalates: the same account can fail every night for months and the only trace is
 * a line per night in a log nobody reads. Meanwhile a family has been told those records
 * were destroyed.
 *
 * The signal is simply that the user ROW still exists past its purge date, since purgeUser
 * deletes it. These tests pin that the check finds a stuck purge, stays quiet when there is
 * nothing wrong, and does not cry wolf over the two cases where survival is CORRECT: a legal
 * hold, and a purge that is merely due rather than overdue.
 */
function harness(users: any[]) {
  const queried: any[] = [];
  const prisma: any = {
    user: {
      findMany: async (args: any) => {
        queried.push(args.where);
        const w = args.where;
        const rows = users.filter((u) => {
          if (u.scheduledPurgeAt == null) return false;
          if (w.scheduledPurgeAt.lt && !(u.scheduledPurgeAt < w.scheduledPurgeAt.lt)) return false;
          if (w.scheduledPurgeAt.gt && !(u.scheduledPurgeAt > w.scheduledPurgeAt.gt)) return false;
          if (w.legalHoldAt === null && u.legalHoldAt != null) return false;
          return true;
        });
        return rows.slice(0, args.take ?? rows.length).map((u) => ({
          id: u.id,
          scheduledPurgeAt: u.scheduledPurgeAt,
          retentionRemindersSent: u.retentionRemindersSent ?? [],
        }));
      },
      count: async ({ where }: any) =>
        where.legalHoldAt?.not === null ? users.filter((u) => u.legalHoldAt != null).length : 0,
    },
  };
  const svc = new DataRetentionService(prisma, { get: () => undefined } as any, {} as any, {} as any, {} as any);
  return { svc, queried };
}

const NOW = new Date('2026-07-29T00:00:00Z');
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000);
const daysFromNow = (n: number) => new Date(NOW.getTime() + n * 86_400_000);

describe('retention reconciliation', () => {
  let errors: string[];
  let warns: string[];
  beforeEach(() => {
    errors = [];
    warns = [];
    jest.spyOn(Logger.prototype, 'error').mockImplementation((m: any) => void errors.push(String(m)));
    jest.spyOn(Logger.prototype, 'warn').mockImplementation((m: any) => void warns.push(String(m)));
  });
  afterEach(() => jest.restoreAllMocks());

  it('raises an ERROR for an account whose purge has been failing', async () => {
    const h = harness([{ id: 'u1', scheduledPurgeAt: daysAgo(9), legalHoldAt: null }]);
    const res = await h.svc.reconcile(NOW);

    expect(res.purgesOverdue).toBe(1);
    expect(res.overdueUserIds).toEqual(['u1']);
    // ERROR not warn: a family was told these records were destroyed and they are still here.
    expect(errors.join()).toContain('u1');
    expect(errors.join()).toMatch(/past their purge date/i);
  });

  it('says NOTHING when every purge has completed', async () => {
    // Purged users are deleted, so a healthy system has no rows to find.
    const h = harness([]);
    const res = await h.svc.reconcile(NOW);
    expect(res).toMatchObject({ purgesOverdue: 0, heldEstates: 0 });
    expect(errors).toEqual([]);
  });

  it('does not cry wolf over a purge that is merely DUE, not overdue', async () => {
    // runDailyPurge runs once a day; a single missed night can be a transient S3 or Stripe
    // failure. Alerting on that would train someone to ignore this alert.
    const h = harness([{ id: 'fresh', scheduledPurgeAt: daysAgo(1), legalHoldAt: null }]);
    expect((await h.svc.reconcile(NOW)).purgesOverdue).toBe(0);
    expect(errors).toEqual([]);
  });

  it('never reports a HELD estate as a failure — not purging it is correct', async () => {
    const h = harness([{ id: 'held', scheduledPurgeAt: daysAgo(400), legalHoldAt: daysAgo(300) }]);
    const res = await h.svc.reconcile(NOW);

    expect(res.purgesOverdue).toBe(0);
    expect(errors).toEqual([]);
    // ...but it is surfaced, because a hold nobody revisits keeps an estate alive forever.
    expect(res.heldEstates).toBe(1);
    expect(warns.join()).toMatch(/legal hold/i);
  });

  it('excludes held estates in the QUERY, not after the fact', async () => {
    // Filtering in SQL matters at scale: this runs nightly over every account.
    const h = harness([]);
    await h.svc.reconcile(NOW);
    expect(h.queried[0]).toMatchObject({ legalHoldAt: null });
  });

  it('bounds how many ids it reports, so an outage does not page a whole table', async () => {
    const many = Array.from({ length: 120 }, (_, i) => ({
      id: `u${i}`,
      scheduledPurgeAt: daysAgo(30),
      legalHoldAt: null,
    }));
    const res = await harness(many).svc.reconcile(NOW);
    expect(res.purgesOverdue).toBe(50);
  });

  // --- the notification half -------------------------------------------------
  // The heirs' 90-day retrieval window only means something if they are TOLD it started.
  // A reminder cron that quietly stops running lets that window expire on people who
  // never knew about it — and unlike a stuck purge, there is no leftover state to notice.

  it('flags an account past a reminder milestone with nothing recorded as sent', async () => {
    const h = harness([{ id: 'quiet', scheduledPurgeAt: daysFromNow(5), legalHoldAt: null, retentionRemindersSent: [] }]);
    const res = await h.svc.reconcile(NOW);

    expect(res.noticesOverdue).toBe(1);
    expect(res.missedNoticeUserIds).toEqual(['quiet']);
    expect(errors.join()).toMatch(/reminder milestone/i);
  });

  it('stays silent once every passed milestone is recorded', async () => {
    // 5 days out: the 30 and 7 thresholds are passed, the 3 is not yet due.
    const h = harness([
      { id: 'ok', scheduledPurgeAt: daysFromNow(5), legalHoldAt: null, retentionRemindersSent: ['30', '7'] },
    ]);
    const res = await h.svc.reconcile(NOW);
    expect(res.noticesOverdue).toBe(0);
    expect(errors).toEqual([]);
  });

  it('gives a full day of slack, so the 2am send and this 4am check never disagree', async () => {
    // Exactly at the 30-day threshold with nothing sent. Today's cron may not have run yet;
    // flagging here would fire an alert every single time an account enters the window.
    const h = harness([{ id: 'edge', scheduledPurgeAt: daysFromNow(30), legalHoldAt: null, retentionRemindersSent: [] }]);
    expect((await h.svc.reconcile(NOW)).noticesOverdue).toBe(0);

    // One day later the milestone is genuinely missed.
    const late = harness([{ id: 'edge', scheduledPurgeAt: daysFromNow(29), legalHoldAt: null, retentionRemindersSent: [] }]);
    expect((await late.svc.reconcile(NOW)).noticesOverdue).toBe(1);
  });

  it('never chases notices for a HELD estate — its countdown is suspended, not late', async () => {
    const h = harness([
      { id: 'held', scheduledPurgeAt: daysFromNow(5), legalHoldAt: daysAgo(2), retentionRemindersSent: [] },
    ]);
    const res = await h.svc.reconcile(NOW);
    expect(res.noticesOverdue).toBe(0);
    expect(res.heldEstates).toBe(1);
  });
});
