import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { CreditsModule } from '../credits/credits.module';
import { ReferralsController } from './referrals.controller';
import { ReferralsService } from './referrals.service';

@Module({
  imports: [PrismaModule, CreditsModule],
  controllers: [ReferralsController],
  providers: [ReferralsService],
  exports: [ReferralsService], // PaymentsService calls this from the payment webhook
})
export class ReferralsModule {}
