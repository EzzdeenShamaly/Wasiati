import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { ZakatController } from './zakat.controller';
import { ZakatService } from './zakat.service';
import { GoldPriceService } from './gold-price.service';

@Module({
  imports: [PrismaModule],
  controllers: [ZakatController],
  providers: [ZakatService, GoldPriceService],
  exports: [ZakatService],
})
export class ZakatModule {}
