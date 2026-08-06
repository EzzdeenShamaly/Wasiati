import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { Queue } from 'bullmq';

export interface MailJob {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

/** Enqueues transactional emails for async, retried delivery. */
@Injectable()
export class MailQueue {
  constructor(@InjectQueue('mail') private queue: Queue<MailJob>) {}

  async enqueue(job: MailJob): Promise<void> {
    await this.queue.add('send', job, {
      attempts: 3,
      backoff: { type: 'exponential', delay: 2000 },
      removeOnComplete: true,
      removeOnFail: 200,
    });
  }
}
