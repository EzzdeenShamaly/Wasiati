import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { MailQueue } from './mail.queue';
import { MailProcessor } from './mail.processor';

@Module({
  imports: [BullModule.registerQueue({ name: 'mail' })],
  providers: [MailQueue, MailProcessor],
  exports: [MailQueue],
})
export class MailModule {}
