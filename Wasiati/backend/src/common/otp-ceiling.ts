import { createHash } from 'crypto';
import { Logger } from '@nestjs/common';

/**
 * A ceiling on one-time codes sent to ONE destination — the limit an IP-rotating attacker
 * cannot shed.
 *
 * Every OTP endpoint in this app carries a @Throttle, and every one of those is keyed by IP:
 * they bound a caller, not a target. That gap matters more here than it would elsewhere,
 * because OtpService.verify reads only the NEWEST unconsumed code for a
 * (destination, purpose) pair. So repeated requests naming one person supersede that
 * person's real code: whatever arrived a moment ago stops being the one the server will
 * check. Slowly it is spam and confusion; at the rate IP rotation allows it is an effective
 * lockout — of a witness from signing, a trustee from confirming a release, an heir from a
 * will already released to them. And every attempt bills a message aimed at a number the
 * attacker chooses and the operator pays for: $0.1949 each in KSA.
 *
 * The authenticated paths (login MFA, phone verification) already defend this, counting
 * OtpCode rows per destination precisely so the limit "survives IP rotation" — see
 * AuthService. The unauthenticated ones, which are the ones a stranger can reach, mostly
 * did not. This is the shared door they now go through.
 *
 * Returns false when the code must NOT be sent. Callers are expected to stay silent about
 * that: these endpoints answer with a constant body by design, and "rate limited" would
 * confirm that the person exists on a dead person's will.
 */
export interface OtpCeilingLimits {
  perHour: number;
  perDay: number;
}

export interface CounterPort {
  incrWithTtl(key: string, ttlSeconds: number): Promise<number>;
}

export async function withinOtpCeiling(
  counter: CounterPort,
  logger: Logger,
  scope: string,
  destination: string,
  limits: OtpCeilingLimits,
): Promise<boolean> {
  // Hashed: these keys sit in a cache with a different blast radius from the database, and
  // a phone number is PII wherever it lands.
  const dest = createHash('sha256').update(destination).digest('hex').slice(0, 32);
  const checks: [string, number, number][] = [
    [`otp:${scope}:${dest}:h`, 60 * 60, limits.perHour],
    [`otp:${scope}:${dest}:d`, 24 * 60 * 60, limits.perDay],
  ];

  try {
    for (const [key, ttl, limit] of checks) {
      const count = await counter.incrWithTtl(key, ttl);
      if (count > limit) {
        logger.warn(`OTP ceiling hit on ${key} (${count} > ${limit}); no code sent.`);
        return false;
      }
    }
    return true;
  } catch (e) {
    // Fails CLOSED, matching the claim lookup's existing ceiling. An unavailable limit must
    // not quietly become no limit — this is the only one an attacker cannot shed by changing
    // IP. The cost is real and worth naming: while the counter is down, nobody can request a
    // code on these paths, and because the responses are constant they are told one was sent.
    logger.error(`OTP ceiling unavailable for ${scope} (${(e as Error).message}); refusing to send.`);
    return false;
  }
}
