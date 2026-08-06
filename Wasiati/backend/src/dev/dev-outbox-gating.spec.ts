import { DevModule } from './dev.module';
import { NotificationsService } from '../notifications/notifications.service';

/**
 * The dev SMS outbox holds plaintext OTP bodies, so its gate is the only thing
 * standing between local convenience and a production endpoint that hands any caller
 * a live code for any phone number. These tests pin BOTH halves of that gate:
 * the route must not be registered outside dev, and the buffer must stay empty even
 * if it somehow were.
 */
const configWith = (env: Record<string, string | undefined>) =>
  ({ get: (key: string) => env[key] }) as any;

describe('dev SMS outbox — production gating', () => {
  const realNodeEnv = process.env.NODE_ENV;
  const realEcho = process.env.OTP_DEV_ECHO;

  afterEach(() => {
    process.env.NODE_ENV = realNodeEnv;
    process.env.OTP_DEV_ECHO = realEcho;
  });

  describe('DevModule.registerIfEnabled', () => {
    it('registers nothing in production, even if OTP_DEV_ECHO is somehow true', () => {
      process.env.NODE_ENV = 'production';
      process.env.OTP_DEV_ECHO = 'true';
      expect(DevModule.registerIfEnabled()).toEqual([]);
    });

    it('registers nothing in dev unless OTP_DEV_ECHO is explicitly true', () => {
      process.env.NODE_ENV = 'development';
      process.env.OTP_DEV_ECHO = undefined;
      expect(DevModule.registerIfEnabled()).toEqual([]);

      process.env.OTP_DEV_ECHO = 'false';
      expect(DevModule.registerIfEnabled()).toEqual([]);
    });

    it('registers the module for local dev with the flag on', () => {
      process.env.NODE_ENV = 'development';
      process.env.OTP_DEV_ECHO = 'true';
      expect(DevModule.registerIfEnabled()).toEqual([DevModule]);
    });
  });

  describe('NotificationsService.readDevOutbox', () => {
    it('captures nothing in production', async () => {
      process.env.NODE_ENV = 'production';
      const svc = new NotificationsService(configWith({ OTP_DEV_ECHO: 'true' }));
      await svc.sendSms('+15559990000', 'Your Wasiati verification code is 424242.');
      expect(svc.readDevOutbox()).toEqual([]);
      expect(svc.readDevOutbox('+15559990000')).toEqual([]);
    });

    it('captures nothing in dev while the flag is off', async () => {
      process.env.NODE_ENV = 'development';
      const svc = new NotificationsService(configWith({ OTP_DEV_ECHO: undefined }));
      await svc.sendSms('+15559990000', 'Your Wasiati verification code is 424242.');
      expect(svc.readDevOutbox()).toEqual([]);
    });

    it('captures the body for local dev, newest first, filtered by destination', async () => {
      process.env.NODE_ENV = 'development';
      const svc = new NotificationsService(configWith({ OTP_DEV_ECHO: 'true' }));
      await svc.sendSms('+15559990000', 'first');
      await svc.sendSms('+15550000001', 'someone else');
      await svc.sendSms('+15559990000', 'second');

      const mine = svc.readDevOutbox('+15559990000');
      expect(mine.map((m) => m.body)).toEqual(['second', 'first']);
      expect(mine.every((m) => m.channel === 'sms')).toBe(true);
      expect(svc.readDevOutbox()).toHaveLength(3);
    });

    it('matches a destination regardless of spacing/dashes', async () => {
      process.env.NODE_ENV = 'development';
      const svc = new NotificationsService(configWith({ OTP_DEV_ECHO: 'true' }));
      await svc.sendSms('+1 555-999-0000', 'code inside');
      expect(svc.readDevOutbox('+15559990000').map((m) => m.body)).toEqual(['code inside']);
    });

    it('evicts oldest beyond the cap so a long-running dev server cannot grow forever', async () => {
      process.env.NODE_ENV = 'development';
      const svc = new NotificationsService(configWith({ OTP_DEV_ECHO: 'true' }));
      for (let i = 0; i < 55; i++) await svc.sendSms('+15559990000', `msg ${i}`);
      const all = svc.readDevOutbox();
      expect(all).toHaveLength(50);
      expect(all[0].body).toBe('msg 54'); // newest retained
      expect(all[all.length - 1].body).toBe('msg 5'); // 0-4 evicted
    });
  });
});
