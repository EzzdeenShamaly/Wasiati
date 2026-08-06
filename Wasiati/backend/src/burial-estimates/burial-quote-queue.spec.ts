import { BurialEstimatesService, QUOTED_QUEUE_DAYS } from './burial-estimates.service';

/**
 * The admin burial-quote queue is the ONLY way to find a request awaiting a quote —
 * the user-facing GET is scoped to the caller's own estimates. The bug this suite
 * pins: this list route did not exist at all, so "Request a real quote" flipped the
 * row to QUOTE_REQUESTED and nobody could ever answer it (the notification email was
 * the sole trace, and an email is not a queue).
 */

const DAY = 24 * 60 * 60 * 1000;

function makeService(rows: any[] = []) {
  const captured: { where?: any; include?: any; orderBy?: any } = {};
  const prisma: any = {
    burialEstimateRequest: {
      findMany: async (args: any) => {
        captured.where = args.where;
        captured.include = args.include;
        captured.orderBy = args.orderBy;
        return rows;
      },
    },
  };
  const svc = new BurialEstimatesService(prisma, {} as any);
  return { svc, captured };
}

describe('listQuoteQueue — what the admin queue asks the database for', () => {
  it('includes QUOTE_REQUESTED unconditionally: a waiting client must never age out', async () => {
    const { svc, captured } = makeService();
    await svc.listQuoteQueue();

    const waiting = captured.where.OR.find((c: any) => c.status === 'QUOTE_REQUESTED');
    // Unconditional means exactly that — no date clause that could expire a request
    // nobody has answered yet.
    expect(Object.keys(waiting)).toEqual(['status']);
  });

  it('keeps QUOTED rows only within the window, keyed off quotedAt', async () => {
    const { svc, captured } = makeService();
    const before = Date.now() - QUOTED_QUEUE_DAYS * DAY;
    await svc.listQuoteQueue();
    const after = Date.now() - QUOTED_QUEUE_DAYS * DAY;

    const quoted = captured.where.OR.find((c: any) => c.status === 'QUOTED');
    // quotedAt, not createdAt — a slow answer must not expire the moment it is given.
    expect(quoted.quotedAt.gte.getTime()).toBeGreaterThanOrEqual(before);
    expect(quoted.quotedAt.gte.getTime()).toBeLessThanOrEqual(after);
  });

  it('never lists ESTIMATED, CONFIRMED or CANCELLED rows — nobody is waiting on those', async () => {
    const { svc, captured } = makeService();
    await svc.listQuoteQueue();

    const statuses = captured.where.OR.map((c: any) => c.status);
    expect(statuses.sort()).toEqual(['QUOTED', 'QUOTE_REQUESTED']);
  });

  it('carries who to call for: the requesting user, oldest request first', async () => {
    const { svc, captured } = makeService();
    await svc.listQuoteQueue();

    // The admin has to phone mosques in this person's city — a queue without the
    // requester's contact details is unanswerable.
    expect(captured.include.user.select).toMatchObject({ email: true, phone: true, region: true });
    expect(captured.orderBy).toEqual({ createdAt: 'asc' });
  });
});
