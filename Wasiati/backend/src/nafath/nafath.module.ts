import { Module } from '@nestjs/common';
import { NafathService } from './nafath.service';
import { NafathController } from './nafath.controller';

@Module({
  controllers: [NafathController],
  providers: [NafathService],
  exports: [NafathService],
})
export class NafathModule {}
