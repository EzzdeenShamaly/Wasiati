import { PortalService } from './portal.service';

/**
 * A ceiling on codes sent to ONE destination — the limit an IP-rotating attacker cannot shed.
 *
 * The @Throttle on POST /portal/start is keyed by IP, so it bounds a caller, not a target.
 * Nothing bounded the target, and OtpService.verify reads only the NEWEST unconsumed code
 * for a (destination, purpose) pair. So repeated calls naming one heir's address supersede
 * that heir's real code: whatever just arrived stops being the one the server will check.
 * Slowly that is spam and confusion; at the rate IP rotation allows it is an effective
 * lockout of a grieving family from a released will — and every attempt bills a message,
 * $0.1949 of it in KSA.
 *
 * The claim lookup — the other unauthenticated door into a dead person's estate — has had a
 * destination-keyed ceiling all along. This is the portal catching up.
 */
function portalWith(redis: any, sent: string[]) {
  const prisma: any = {
    deathClaim: {
      findMany: async () => [
        {
          id: 'claim-1',
          status: 'RELEASED',
          willId: 'will-1',
          will: {
            owner: { email: 'owner@x.com' },
            heirContacts: [{ id: 'heir-1', phone: null, email: 'heir@x.com' }],
            trustees: [],
          },
        },
      ],
    },
    claimAccessToken: { create: async () => ({}) },
  };
  const otp: any = {
    issue: async (destination: string) => {
      sent.push(destination);
      return '123456';
    },
  };
  return new PortalService(
    prisma,
    otp,
    {} as any,
    { log: async () => undefined } as any,
    { get: () => undefined } as any,
    {} as any,
    redis,
  );
}

/** Counts per key the way Redis INCR does, so the limits are exercised, not stubbed past. */
const countingRedis = () => {
  const counts = new Map<string, number>();
  return {
    counts,
    incrWithTtl: async (key: string) => {
      const n = (counts.get(key) ?? 0) + 1;
      counts.set(key, n);
      return n;
    },
  };
};

describe('portal sign-in is bounded per destination', () => {
  it('sends while under the hourly ceiling and stops at it', async () => {
    const sent: string[] = [];
    const svc = portalWith(countingRedis(), sent);

    for (let i = 0; i < 5; i++) await svc.start('HEIR' as any, 'heir@x.com');
    expect(sent).toHaveLength(5); // perDestinationPerHour

    // The sixth is the one that would have superseded the fifth code in the heir's inbox.
    await svc.start('HEIR' as any, 'heir@x.com');
    await svc.start('HEIR' as any, 'heir@x.com');
    expect(sent).toHaveLength(5);
  });

  it('keys the ceiling on the DESTINATION, not the address that was typed', async () => {
    // Both keys must mention the destination and neither may be a global counter, or one
    // busy heir would lock out every other heir on the platform.
    const redis = countingRedis();
    const svc = portalWith(redis, []);
    await svc.start('HEIR' as any, 'heir@x.com');
    const keys = [...redis.counts.keys()];
    expect(keys).toHaveLength(2); // an hourly and a daily window
    for (const k of keys) expect(k).toMatch(/^portal:start:dest:[0-9a-f]{32}:[hd]$/);
  });

  it('still answers { sent: true } when suppressed, so it is not an oracle', async () => {
    // "Rate limited" would confirm the address is on a dead person's roster — the exact
    // thing the constant response exists to hide.
    const sent: string[] = [];
    const svc = portalWith(countingRedis(), sent);
    for (let i = 0; i < 8; i++) {
      await expect(svc.start('HEIR' as any, 'heir@x.com')).resolves.toEqual({ sent: true });
    }
    expect(sent).toHaveLength(5);
  });

  it('fails CLOSED when the counter is unavailable', async () => {
    // Deliberate, and it has a cost: while Redis is down no heir can start a session, and
    // the constant response tells them a code was sent. An unavailable limit must not
    // quietly become no limit — this is the one an attacker cannot shed by changing IP.
    const sent: string[] = [];
    const svc = portalWith(
      { incrWithTtl: async () => { throw new Error('ECONNREFUSED'); } },
      sent,
    );
    await expect(svc.start('HEIR' as any, 'heir@x.com')).resolves.toEqual({ sent: true });
    expect(sent).toEqual([]);
  });
});
