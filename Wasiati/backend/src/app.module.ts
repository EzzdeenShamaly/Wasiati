import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { HealthController } from './common/health.controller';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { validateEnv } from './common/env.validation';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { LoggerModule } from 'nestjs-pino';
import { AuditModule } from './common/audit/audit.module';
import { QueueModule } from './queue/queue.module';
import { MailModule } from './mail/mail.module';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { WillsModule } from './wills/wills.module';
import { WitnessesModule } from './witnesses/witnesses.module';
import { TrusteesModule } from './trustees/trustees.module';
import { HeirContactsModule } from './heir-contacts/heir-contacts.module';
import { DirectivesModule } from './directives/directives.module';
import { VaultModule } from './vault/vault.module';
import { DeathClaimsModule } from './death-claims/death-claims.module';
import { PortalModule } from './portal/portal.module';
import { PaymentsModule } from './payments/payments.module';
import { NotificationsModule } from './notifications/notifications.module';
import { AssetsModule } from './assets/assets.module';
import { AiIntakeModule } from './ai-intake/ai-intake.module';
import { BurialEstimatesModule } from './burial-estimates/burial-estimates.module';
import { EntitlementsModule } from './entitlements/entitlements.module';
import { CommerceModule } from './commerce/commerce.module';
import { ReferralsModule } from './referrals/referrals.module';
import { CreditsModule } from './credits/credits.module';
import { IdentityModule } from './identity/identity.module';
import { NafathModule } from './nafath/nafath.module';
import { ZakatModule } from './zakat/zakat.module';
import { FilesModule } from './files/files.module';
import { CheckinModule } from './checkin/checkin.module';
import { ContentModule } from './content/content.module';
import { DataRetentionModule } from './data-retention/data-retention.module';
import { MetricsModule } from './metrics/metrics.module';
import { DevModule } from './dev/dev.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    // Structured JSON logging with request ids; secrets are redacted. Pretty in dev.
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
        transport:
          process.env.NODE_ENV === 'production'
            ? undefined
            : { target: 'pino-pretty', options: { singleLine: true, translateTime: 'SYS:HH:MM:ss' } },
        redact: [
          'req.headers.authorization',
          'req.headers.cookie',
          'req.body.password',
          'req.body.newPassword',
          'req.body.token',
        ],
        customProps: () => ({ region: process.env.REGION }),
      },
    }),
    // Global rate limit. Made configurable ONLY so the integration suite can run: it
    // issues well over 100 requests in a minute, so against the fixed limit every
    // integration test was rate-limited. That used to pass silently — the tests caught the
    // 429 and skipped — which is how "All tests passed!" came to mean "nothing ran".
    // The suite now hard-fails on a 429, so the limit must be raisable locally or the
    // tests cannot run at all. Defaults are unchanged: production behaves identically
    // unless the environment explicitly says otherwise.
    // forRootAsync, NOT forRoot: the array passed to forRoot is evaluated at import time,
    // before ConfigModule has loaded .env into process.env, so the override silently read
    // as undefined and the limit stayed at 100. Resolving through ConfigService defers it
    // until after config is loaded.
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => [
        {
          ttl: Number(config.get('THROTTLE_TTL_MS')) || 60000,
          limit: Number(config.get('THROTTLE_LIMIT')) || 100,
        },
      ],
    }),
    ScheduleModule.forRoot(),
    AuditModule,
    QueueModule,
    MailModule,
    PrismaModule,
    RedisModule,
    NotificationsModule,
    AuthModule,
    UsersModule,
    WillsModule,
    WitnessesModule,
    TrusteesModule,
    HeirContactsModule,
    DirectivesModule,
    VaultModule,
    DeathClaimsModule,
    PortalModule,
    PaymentsModule,
    AssetsModule,
    AiIntakeModule,
    BurialEstimatesModule,
    EntitlementsModule,
    CommerceModule,
    ReferralsModule,
    CreditsModule,
    IdentityModule,
    NafathModule,
    ZakatModule,
    FilesModule,
    CheckinModule,
    ContentModule,
    DataRetentionModule,
    MetricsModule,
    // Local-dev only (see DevModule.registerIfEnabled); resolves to nothing in
    // production. MUST stay after ConfigModule.forRoot() above, which is what puts
    // .env into process.env for the gate to read.
    ...DevModule.registerIfEnabled(),
  ],
  controllers: [HealthController],
  providers: [
    // Enforce rate limiting globally. Without this APP_GUARD registration the
    // ThrottlerModule config is inert — limits are only applied when the guard runs.
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    // Normalise errors + never leak Prisma/internal detail to clients.
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
  ],
})
export class AppModule {}
