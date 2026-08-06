import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { HeirContactsService } from './heir-contacts.service';
import { HeirContactsController } from './heir-contacts.controller';

@Module({
  imports: [AuthModule],
  controllers: [HeirContactsController],
  providers: [HeirContactsService],
  exports: [HeirContactsService],
})
export class HeirContactsModule {}
