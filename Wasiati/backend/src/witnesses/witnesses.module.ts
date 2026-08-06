import { Module } from '@nestjs/common';
import { WitnessesService } from './witnesses.service';
import { WitnessesController } from './witnesses.controller';
import { AuthModule } from '../auth/auth.module';
import { WillsModule } from '../wills/wills.module';

@Module({
  imports: [AuthModule, WillsModule],
  controllers: [WitnessesController],
  providers: [WitnessesService],
  exports: [WitnessesService],
})
export class WitnessesModule {}
