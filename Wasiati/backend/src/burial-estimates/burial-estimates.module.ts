import { Module } from '@nestjs/common';
import { BurialEstimatesService } from './burial-estimates.service';
import { BurialEstimatesController } from './burial-estimates.controller';
import { BurialEstimatesAdminController } from './burial-estimates-admin.controller';

@Module({
  controllers: [BurialEstimatesController, BurialEstimatesAdminController],
  providers: [BurialEstimatesService],
  exports: [BurialEstimatesService],
})
export class BurialEstimatesModule {}
