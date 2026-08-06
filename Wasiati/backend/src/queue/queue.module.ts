import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigModule, ConfigService } from '@nestjs/config';

/** BullMQ root — shares the same Redis as the app (REDIS_URL). */
@Module({
  imports: [
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const url = new URL(config.get<string>('REDIS_URL') ?? 'redis://localhost:6379');
        return {
          connection: {
            host: url.hostname,
            port: Number(url.port || 6379),
            username: url.username || undefined,
            password: url.password || undefined,
            // This parse used to DROP the scheme, so `rediss://` (ElastiCache with
            // in-transit encryption) silently connected without TLS and failed —
            // while RedisService, which passes the URL to ioredis whole, worked.
            // Half the app on an encrypted Redis and half not is exactly the bug
            // you cannot see locally, where dev Redis is plain `redis://`.
            tls: url.protocol === 'rediss:' ? {} : undefined,
          },
        };
      },
    }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
