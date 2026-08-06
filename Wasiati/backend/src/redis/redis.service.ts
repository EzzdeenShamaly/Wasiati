import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * Thin ioredis wrapper. Used for short-lived, security-sensitive state that must
 * NOT live in the JWT or be trusted from the client — currently the WebAuthn
 * passkey challenge, and available for BullMQ / caching in later phases.
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  readonly client: Redis;

  constructor(config: ConfigService) {
    const url = config.get<string>('REDIS_URL') ?? 'redis://localhost:6379';
    this.client = new Redis(url, { maxRetriesPerRequest: null });
    this.client.on('error', (e) => this.logger.error(`Redis error: ${e.message}`));
  }

  /** Store a JSON value with a TTL (seconds). */
  async setJson(key: string, value: unknown, ttlSeconds: number): Promise<void> {
    await this.client.set(key, JSON.stringify(value), 'EX', ttlSeconds);
  }

  /** Read and JSON-parse a value, or null if absent/expired. */
  async getJson<T>(key: string): Promise<T | null> {
    const raw = await this.client.get(key);
    return raw ? (JSON.parse(raw) as T) : null;
  }

  /** Atomically read-and-delete — used for single-use challenges. */
  async takeJson<T>(key: string): Promise<T | null> {
    const raw = await this.client.getdel(key);
    return raw ? (JSON.parse(raw) as T) : null;
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  /**
   * Increment a counter and return its new value, setting the TTL only on the
   * first increment so the window is fixed-length rather than sliding-and-never-
   * expiring.
   *
   * INCR and EXPIRE are pipelined into one round trip, and EXPIRE is issued with
   * `NX` so a later increment inside the window cannot push the expiry out. Without
   * NX, a caller hitting the limit repeatedly would keep renewing the TTL and lock
   * themselves out forever; with it, the window always ends `ttlSeconds` after the
   * first hit.
   *
   * Used for abuse counters that must survive IP rotation (per-will and
   * per-destination claim-lookup limits) — those cannot live in the per-IP
   * throttler, which is exactly what an attacker rotates away from.
   */
  async incrWithTtl(key: string, ttlSeconds: number): Promise<number> {
    const res = await this.client.multi().incr(key).expire(key, ttlSeconds, 'NX').exec();
    // ioredis returns [[err, value], ...]; a null reply means the MULTI was discarded.
    const first = res?.[0];
    if (!first || first[0]) {
      throw first?.[0] ?? new Error('Redis INCR failed');
    }
    return Number(first[1]);
  }

  onModuleDestroy(): void {
    this.client.disconnect();
  }
}
