import { Logger } from '@nestjs/common';
import { MailProcessor } from './mail.processor';

/**
 * Email verification and the password-reset LINK both ride this queue. sendEmail
 * returns false — WITHOUT throwing — when no SMTP transport is configured, and the
 * worker used to ignore that: it logged `Delivered`, the job completed, and because the
 * queue is removeOnComplete nothing was left behind. So transactional mail could be
 * entirely dark while both the logs and the failed-job set insisted it was fine.
 *
 * A dropped message must fail the job instead: BullMQ then retries, and a job that
 * exhausts its attempts stays visible in the failed set where an operator can see it.
 */
describe('MailProcessor', () => {
  const job = { data: { to: 'a@b.test', subject: 'Verify your Wasiati email', text: 'hello' } } as any;

  it('logs Delivered only when the transport actually dispatched', async () => {
    const notifications = { sendEmail: jest.fn().mockResolvedValue(true) } as any;
    const logged = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);

    await expect(new MailProcessor(notifications).process(job)).resolves.toBeUndefined();
    expect(notifications.sendEmail).toHaveBeenCalledWith('a@b.test', 'Verify your Wasiati email', 'hello', undefined);
    expect(logged).toHaveBeenCalledWith(expect.stringContaining('Delivered'));
    logged.mockRestore();
  });

  it('FAILS the job when the mail was dropped, and never claims delivery', async () => {
    const notifications = { sendEmail: jest.fn().mockResolvedValue(false) } as any;
    const logged = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);

    await expect(new MailProcessor(notifications).process(job)).rejects.toThrow(/dropped/i);
    expect(logged).not.toHaveBeenCalledWith(expect.stringContaining('Delivered'));
    logged.mockRestore();
  });

  it('lets a transport exception through so the retry/backoff still applies', async () => {
    const notifications = { sendEmail: jest.fn().mockRejectedValue(new Error('smtp refused')) } as any;
    await expect(new MailProcessor(notifications).process(job)).rejects.toThrow('smtp refused');
  });
});
