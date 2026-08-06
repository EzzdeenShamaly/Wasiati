import { CRON_LOCKS, withCronLock } from './cron-lock';

/**
 * The fence that makes >1 API task safe to run. Every @Cron used to fire on every
 * running task — an ECS rolling deploy briefly runs two even at desiredCount 1 —
 * so retention deletions ran twice and subscription renewals CHARGED twice.
 *
 * pg_try_advisory_xact_lock semantics pinned here: the winner runs the job inside
 * the lock-holding transaction; the loser SKIPS (returns undefined), never queues;
 * and a throwing job still surrenders the lock because it is transaction-scoped.
 */
function makePrisma(locked: boolean) {
  const calls: any[] = [];
  const tx = {
    $queryRaw: jest.fn(async (strings: TemplateStringsArray, ..._values: any[]) => {
      calls.push(strings.join('?'));
      return [{ locked }];
    }),
  };
  const prisma: any = {
    $transaction: jest.fn(async (fn: any, _opts: any) => fn(tx)),
  };
  return { prisma, tx, calls };
}

describe('withCronLock', () => {
  it('runs the job when the lock is free, and returns its result', async () => {
    const { prisma } = makePrisma(true);
    const job = jest.fn(async () => 'renewed 3');
    const res = await withCronLock(prisma, CRON_LOCKS.subscriptionRenewals, 'billing', job);
    expect(res).toBe('renewed 3');
    expect(job).toHaveBeenCalledTimes(1);
  });

  it('SKIPS when another instance holds the lock — never queues behind it', async () => {
    const { prisma } = makePrisma(false);
    const job = jest.fn();
    const res = await withCronLock(prisma, CRON_LOCKS.subscriptionRenewals, 'billing', job);
    expect(res).toBeUndefined();
    expect(job).not.toHaveBeenCalled();
  });

  it('uses the try-lock, transaction-scoped form', async () => {
    const { prisma, calls } = makePrisma(true);
    await withCronLock(prisma, CRON_LOCKS.filesReaper, 'reaper', async () => undefined);
    expect(calls[0]).toContain('pg_try_advisory_xact_lock');
  });

  it('propagates a job failure (the transaction rollback is what frees the lock)', async () => {
    const { prisma } = makePrisma(true);
    await expect(
      withCronLock(prisma, CRON_LOCKS.retentionPurge, 'purge', async () => {
        throw new Error('midway crash');
      }),
    ).rejects.toThrow('midway crash');
  });

  it('every job has a distinct lock id — one job running never blocks a different one', () => {
    const ids = Object.values(CRON_LOCKS);
    expect(new Set(ids.map(String)).size).toBe(ids.length);
  });
});
