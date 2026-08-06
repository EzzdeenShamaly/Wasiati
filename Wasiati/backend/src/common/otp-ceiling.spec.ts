import { Logger } from '@nestjs/common';
import { withinOtpCeiling } from './otp-ceiling';

/**
 * The limit an IP-rotating attacker cannot shed.
 *
 * Every OTP route carries a @Throttle keyed by IP, which bounds a caller and not a target.
 * That gap bites hard here because OtpService.verify reads only the NEWEST unconsumed code
 * for a (destination, purpose) pair: repeated requests naming one person supersede the code
 * already in that person's hand. Slowly it is spam; at the rate IP rotation allows it keeps
 * a witness from signing, a trustee from confirming a release, or an heir out of a will that
 * has already been released to them — and bills a message for every attempt.
 */
const LIMITS = { perHour: 3, perDay: 5 };

function counting() {
  const counts = new Map<string, number>();
  return {
    counts,
    incrWithTtl: async (key: string) => {
      const n = (counts.get(key) ?? 0) + 1;
      counts.set(key, n);
      return n;
    },
  };
}

describe('withinOtpCeiling', () => {
  let logger: Logger;
  beforeEach(() => {
    logger = new Logger('test');
    jest.spyOn(logger, 'warn').mockImplementation(() => undefined);
    jest.spyOn(logger, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  it('allows up to the hourly limit and then refuses', async () => {
    const c = counting();
    const ask = () => withinOtpCeiling(c, logger, 'witness:sign', '+15551230000', LIMITS);
    expect(await ask()).toBe(true);
    expect(await ask()).toBe(true);
    expect(await ask()).toBe(true);
    expect(await ask()).toBe(false);
  });

  it('counts each destination separately — one busy phone must not silence another', async () => {
    const c = counting();
    for (let i = 0; i < 4; i++) await withinOtpCeiling(c, logger, 'witness:sign', '+15551230000', LIMITS);
    expect(await withinOtpCeiling(c, logger, 'witness:sign', '+15559990000', LIMITS)).toBe(true);
  });

  it('counts each scope separately — signing and confirming are different acts', async () => {
    const c = counting();
    for (let i = 0; i < 4; i++) await withinOtpCeiling(c, logger, 'witness:sign', '+15551230000', LIMITS);
    expect(await withinOtpCeiling(c, logger, 'trustee:confirm', '+15551230000', LIMITS)).toBe(true);
  });

  it('never puts the raw destination in a cache key', async () => {
    // These keys live in a cache with a different blast radius from the database, and a
    // phone number is PII wherever it lands.
    const c = counting();
    await withinOtpCeiling(c, logger, 'witness:sign', '+966555123456', LIMITS);
    const keys = [...c.counts.keys()];
    expect(keys).toHaveLength(2); // one hourly window, one daily
    for (const k of keys) {
      expect(k).not.toContain('966555123456');
      expect(k).toMatch(/^otp:witness:sign:[0-9a-f]{32}:[hd]$/);
    }
  });

  it('holds the DAILY ceiling even when hourly windows would have reset', async () => {
    // Simulates the clock rolling: the hourly key is dropped, the daily one persists.
    const c = counting();
    for (let i = 0; i < 5; i++) {
      for (const k of [...c.counts.keys()]) if (k.endsWith(':h')) c.counts.delete(k);
      await withinOtpCeiling(c, logger, 'witness:sign', '+15551230000', LIMITS);
    }
    for (const k of [...c.counts.keys()]) if (k.endsWith(':h')) c.counts.delete(k);
    expect(await withinOtpCeiling(c, logger, 'witness:sign', '+15551230000', LIMITS)).toBe(false);
  });

  it('fails CLOSED when the counter is unavailable', async () => {
    // An unavailable limit must not quietly become no limit — this is the only control an
    // attacker cannot shed by changing IP. The cost is stated where it is taken: while the
    // counter is down, these paths send nothing.
    const broken = { incrWithTtl: async () => { throw new Error('ECONNREFUSED'); } };
    expect(await withinOtpCeiling(broken, logger, 'witness:sign', '+15551230000', LIMITS)).toBe(false);
  });
});
