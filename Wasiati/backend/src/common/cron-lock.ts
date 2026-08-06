import { Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * One instance runs each cron; the others skip.
 *
 * Every @Cron in this codebase fires on EVERY running task. With one Fargate task
 * that is fine; with two — an ECS rolling deploy briefly runs two even at
 * desiredCount 1 — retention deletions run twice and subscription renewals CHARGE
 * TWICE. A Postgres advisory lock is the natural fence: it lives in the database
 * the job is about to mutate, costs one round trip, and vanishes automatically
 * when the session ends, so a crashed task can never wedge the lock shut.
 *
 * `pg_try_advisory_lock` (not the blocking form): a second instance must SKIP the
 * run, not queue behind the first and replay the same job the moment it finishes.
 *
 * Advisory locks are SESSION-scoped, and Prisma runs queries on a pool. Acquiring
 * and releasing on `prisma.$queryRaw` directly could use two different connections
 * — releasing a lock we never held while the real one leaks until the pooled
 * connection dies. The interactive transaction pins one connection for both the
 * try-lock and the unlock, with a generous timeout since these jobs do real work.
 */
const logger = new Logger('CronLock');

/** Stable lock ids per job. 64-bit space; these only need to differ from each other. */
export const CRON_LOCKS = {
  subscriptionRenewals: 7_401n,
  retentionSweep: 7_402n,
  checkinSweep: 7_403n,
  filesReaper: 7_404n,
  retentionPurge: 7_405n,
  retentionNotices: 7_406n,
  retentionReconcile: 7_407n,
  goldPriceRefresh: 7_408n,
} as const;

export async function withCronLock<T>(
  prisma: PrismaService,
  lockId: bigint,
  jobName: string,
  fn: () => Promise<T>,
): Promise<T | undefined> {
  return prisma.$transaction(
    async (tx) => {
      const rows = await tx.$queryRaw<{ locked: boolean }[]>`SELECT pg_try_advisory_xact_lock(${lockId}) AS locked`;
      if (!rows[0]?.locked) {
        // Another instance is already running this job — correct, not an error.
        logger.log(`${jobName}: another instance holds the lock — skipping this run.`);
        return undefined;
      }
      // xact-scoped lock: released automatically when this transaction ends, even
      // if fn() throws — there is no unlock call to forget.
      return fn();
    },
    // These jobs iterate real rows (renewals, purges); give them room. The lock is
    // held for the duration, which is exactly the point.
    { timeout: 15 * 60 * 1000, maxWait: 10_000 },
  );
}
