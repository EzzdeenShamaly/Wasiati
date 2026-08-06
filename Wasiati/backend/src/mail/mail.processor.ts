import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { NotificationsService } from '../notifications/notifications.service';
import { MailJob } from './mail.queue';

/** Worker that delivers queued emails via the notifications transport (SES/Mailhog). */
@Processor('mail')
export class MailProcessor extends WorkerHost {
  private readonly logger = new Logger(MailProcessor.name);

  constructor(private notifications: NotificationsService) {
    super();
  }

  async process(job: Job<MailJob>): Promise<void> {
    const delivered = await this.notifications.sendEmail(
      job.data.to,
      job.data.subject,
      job.data.text,
      job.data.html,
    );
    // sendEmail returns false WITHOUT throwing when no SMTP transport is configured.
    // Ignoring that logged "Delivered" over a message that went nowhere and completed
    // the job — and because the queue is removeOnComplete, no failed-job record survived
    // either. Email verification and password-reset links ride this queue, so the whole
    // thing could be dark while the logs and the failed set both said everything was fine.
    // Throwing lets BullMQ retry, and a job that exhausts its attempts stays visible.
    if (!delivered) {
      throw new Error(`Mail transport dropped "${job.data.subject}" — no SMTP transport configured.`);
    }
    this.logger.log(`Delivered mail "${job.data.subject}" to ${job.data.to}`);
  }
}
