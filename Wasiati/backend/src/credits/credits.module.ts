import { Global, Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CreditsController } from './credits.controller';
import { CreditsService } from './credits.service';

// Credit is consumed at checkout and granted by referrals, so it is a
// cross-cutting concern like Notifications.
@Global()
@Module({
  imports: [PrismaModule],
  controllers: [CreditsController],
  providers: [CreditsService],
  exports: [CreditsService],
})
export class CreditsModule {}
