import { Test } from '@nestjs/testing';
import { ConfigModule } from '@nestjs/config';
import { PortalModule } from './portal.module';
import { PortalController } from './portal.controller';
import { PortalService } from './portal.service';
import { PrismaModule } from '../prisma/prisma.module';
import { AuditModule } from '../common/audit/audit.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { EntitlementsModule } from '../entitlements/entitlements.module';
import { RedisModule } from '../redis/redis.module';
import { RedisService } from '../redis/redis.service';
import { PrismaService } from '../prisma/prisma.service';

/**
 * A DI SMOKE TEST, and it earns its place.
 *
 * Every other spec in this module constructs PortalService with `new` and hand-rolled
 * doubles, which proves the logic and proves NOTHING about whether Nest can build the
 * thing. A missing provider or an unexported dependency is invisible to all of them and
 * shows up as a boot crash — and the backend is not running here to catch it. This
 * compiles the real module graph.
 *
 * The two infrastructure providers are overridden so nothing dials anything. That is not
 * belt-and-braces: RedisService constructs an ioredis client in its CONSTRUCTOR, which
 * `compile()` does run, so building this graph for real would open a retrying socket to
 * localhost:6379 in every CI run. Prisma is stubbed for symmetry (it connects later, in
 * onModuleInit, which compile() does not reach).
 *
 * Writing it also proved its own point twice: the first two runs failed on MailProcessor
 * and PasskeysService, because PortalModule depends — through AuthModule — on modules the
 * app only supplies because they are @Global. That is exactly the class of breakage no
 * amount of `new PortalService(...)` testing can see.
 */
describe('PortalModule wiring', () => {
  it('compiles with every dependency resolvable', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [
        // Global modules the app supplies in production; PortalModule relies on them being
        // global rather than importing them, exactly as the other feature modules do.
        ConfigModule.forRoot({ isGlobal: true, ignoreEnvFile: true }),
        PrismaModule,
        AuditModule,
        // @Global in production and relied upon as such by MailModule (which AuthModule
        // pulls in) — omit it here and the graph fails on MailProcessor, not on anything
        // this test is about.
        NotificationsModule,
        // @Global in production; WillsModule (now imported for the portal's will PDF)
        // reaches EntitlementsService through it.
        EntitlementsModule,
        RedisModule,
        PortalModule,
      ],
    })
      .overrideProvider(PrismaService)
      .useValue({ $connect: async () => undefined, $disconnect: async () => undefined })
      // RedisService opens an ioredis socket in its CONSTRUCTOR, so building the graph for
      // real would dial localhost:6379 and leave a retrying connection behind. Stubbed for
      // the same reason as Prisma: this test is about resolvability, not about I/O.
      .overrideProvider(RedisService)
      .useValue({ client: {}, onModuleDestroy: async () => undefined })
      .compile();

    expect(moduleRef.get(PortalService)).toBeInstanceOf(PortalService);
    expect(moduleRef.get(PortalController)).toBeInstanceOf(PortalController);
    await moduleRef.close();
  });
});
