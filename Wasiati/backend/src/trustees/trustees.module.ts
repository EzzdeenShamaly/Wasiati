import { Module } from '@nestjs/common';
import { TrusteesService } from './trustees.service';
import { TrusteesController } from './trustees.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  controllers: [TrusteesController],
  providers: [TrusteesService],
  exports: [TrusteesService],
})
export class TrusteesModule {}
