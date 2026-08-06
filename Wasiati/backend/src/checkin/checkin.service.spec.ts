import { CheckinFrequency } from '@prisma/client';
import {
  CheckinService,
  CheckinState,
  decideCheckinAction,
  FREQUENCY_DAYS,
  REMINDER_INTERVAL_DAYS,
  REMINDERS_BEFORE_ALERT,
} from './checkin.service';

const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-07-10T00:00:00Z');
const daysAgo = (n: number) => new Date(NOW.getTime() - n * DAY);

const state = (over: Partial<CheckinState> = {}): CheckinState => ({
  checkinEnabled: true,
  checkinFrequency: CheckinFrequency.QUARTERLY, // 91 days
  lastCheckinAt: daysAgo(10),
  checkinRemindersSent: 0,
  checkinAlertedAt: null,
  createdAt: daysAgo(400),
  ...over,
});

describe('decideCheckinAction', () => {
  it('does nothing when the check-in is switched off — nobody is asked unprompted', () => {
    const overdueButOff = state({ checkinEnabled: false, lastCheckinAt: daysAgo(999) });
    expect(decideCheckinAction(overdueButOff, NOW)).toBe('none');
  });

  it('does nothing before the check-in falls due', () => {
    expect(decideCheckinAction(state({ lastCheckinAt: daysAgo(90) }), NOW)).toBe('none');
  });

  it('reminds on the day the check-in falls due', () => {
    expect(decideCheckinAction(state({ lastCheckinAt: daysAgo(91) }), NOW)).toBe('remind');
  });

  it('does NOT remind every night — reminders are spaced out', () => {
    // Overdue by 92 days, one reminder already sent. The next is due 14 days after
    // the first, i.e. at day 105. Running the job tonight must do nothing.
    const s = state({ lastCheckinAt: daysAgo(92), checkinRemindersSent: 1 });
    expect(decideCheckinAction(s, NOW)).toBe('none');
  });

  it('sends the second reminder once the interval has elapsed', () => {
    const s = state({ lastCheckinAt: daysAgo(91 + REMINDER_INTERVAL_DAYS), checkinRemindersSent: 1 });
    expect(decideCheckinAction(s, NOW)).toBe('remind');
  });

  it('alerts the trustee after two unanswered reminders (spec §6)', () => {
    const s = state({ lastCheckinAt: daysAgo(200), checkinRemindersSent: REMINDERS_BEFORE_ALERT });
    expect(decideCheckinAction(s, NOW)).toBe('alert-trustee');
  });

  it('alerts the trustee ONCE, not every night thereafter', () => {
    const s = state({
      lastCheckinAt: daysAgo(200),
      checkinRemindersSent: REMINDERS_BEFORE_ALERT,
      checkinAlertedAt: daysAgo(3),
    });
    expect(decideCheckinAction(s, NOW)).toBe('none');
  });

  it('starts the clock at sign-up for a user who has never confirmed', () => {
    const fresh = state({ lastCheckinAt: null, createdAt: daysAgo(10) });
    expect(decideCheckinAction(fresh, NOW)).toBe('none');

    const stale = state({ lastCheckinAt: null, createdAt: daysAgo(100) });
    expect(decideCheckinAction(stale, NOW)).toBe('remind');
  });

  it('honours each frequency', () => {
    for (const [freq, days] of Object.entries(FREQUENCY_DAYS)) {
      const f = freq as CheckinFrequency;
      expect(decideCheckinAction(state({ checkinFrequency: f, lastCheckinAt: daysAgo(days - 1) }), NOW)).toBe('none');
      expect(decideCheckinAction(state({ checkinFrequency: f, lastCheckinAt: daysAgo(days) }), NOW)).toBe('remind');
    }
  });

  it('is safe to run twice in one day — the second run is a no-op', () => {
    // After a reminder is sent the counter increments; re-deciding must not remind again.
    const afterFirstRun = state({ lastCheckinAt: daysAgo(91), checkinRemindersSent: 1 });
    expect(decideCheckinAction(afterFirstRun, NOW)).toBe('none');
  });

  it('does not fire a burst of back-dated reminders after a long outage', () => {
    // Two years overdue, no reminders sent yet: exactly ONE reminder tonight.
    const s = state({ lastCheckinAt: daysAgo(730), checkinRemindersSent: 0 });
    expect(decideCheckinAction(s, NOW)).toBe('remind');
  });
});

describe('CheckinService', () => {
  function makeDb(user: any, trustees: any[] = []) {
    const users = [user];
    return {
      users,
      prisma: {
        user: {
          findMany: async () => users.filter((u) => u.checkinEnabled),
          findUniqueOrThrow: async () => users[0],
          update: async ({ data }: any) => {
            const u = users[0];
            for (const [k, v] of Object.entries(data)) {
              u[k] = v && typeof v === 'object' && 'increment' in (v as any) ? u[k] + (v as any).increment : v;
            }
            return u;
          },
        },
        trustee: { findMany: async () => trustees },
      } as any,
    };
  }

  const notifications = () => ({ sendEmail: jest.fn(), sendSms: jest.fn() }) as any;

  it('confirming resets the reminder count and clears a trustee alert', async () => {
    const db = makeDb({ id: 'u1', checkinRemindersSent: 2, checkinAlertedAt: new Date() });
    const svc = new CheckinService(db.prisma, notifications());

    await svc.confirmAlive('u1');

    expect(db.users[0].checkinRemindersSent).toBe(0);
    expect(db.users[0].checkinAlertedAt).toBeNull();
    expect(db.users[0].lastCheckinAt).toBeInstanceOf(Date);
  });

  it('switching the check-in ON restarts the clock rather than firing immediately', async () => {
    // An account created years ago must not be reminded the moment it opts in.
    const db = makeDb({ id: 'u1', checkinEnabled: false, checkinRemindersSent: 0, createdAt: daysAgo(900) });
    const svc = new CheckinService(db.prisma, notifications());

    await svc.updateSettings('u1', { checkinEnabled: true });

    expect(db.users[0].lastCheckinAt).toBeInstanceOf(Date);
    expect(decideCheckinAction(db.users[0], NOW)).toBe('none');
  });

  it('a reminder increments the counter and messages the user', async () => {
    const notifs = notifications();
    const db = makeDb({
      id: 'u1',
      email: 'a@x.com',
      phone: '+100',
      checkinEnabled: true,
      checkinFrequency: 'QUARTERLY',
      lastCheckinAt: daysAgo(200),
      checkinRemindersSent: 0,
      checkinAlertedAt: null,
      createdAt: daysAgo(400),
    });

    const res = await new CheckinService(db.prisma, notifs).runDailyCheckins();

    expect(res).toEqual({ reminded: 1, alerted: 0 });
    expect(notifs.sendEmail).toHaveBeenCalledTimes(1);
    expect(notifs.sendSms).toHaveBeenCalledTimes(1);
    expect(db.users[0].checkinRemindersSent).toBe(1);
  });

  it('alerts a confirmed trustee — and does not release anything', async () => {
    const notifs = notifications();
    const db = makeDb(
      {
        id: 'u1',
        email: 'a@x.com',
        phone: null,
        checkinEnabled: true,
        checkinFrequency: 'QUARTERLY',
        lastCheckinAt: daysAgo(300),
        checkinRemindersSent: REMINDERS_BEFORE_ALERT,
        checkinAlertedAt: null,
        createdAt: daysAgo(400),
      },
      [{ id: 't1', email: 't@x.com', phone: '+200', status: 'CONFIRMED' }],
    );

    const res = await new CheckinService(db.prisma, notifs).runDailyCheckins();

    expect(res).toEqual({ reminded: 0, alerted: 1 });
    expect(db.users[0].checkinAlertedAt).toBeInstanceOf(Date);
    // The message must not claim the person has died or that a will is released.
    const body = notifs.sendEmail.mock.calls[0][2] as string;
    expect(body).toMatch(/No will has been released/i);
    expect(body).toMatch(/reviewed by a person/i);
  });

  it('stamps the alert even with no trustee, so it does not retry nightly', async () => {
    const notifs = notifications();
    const db = makeDb(
      {
        id: 'u1',
        email: 'a@x.com',
        phone: null,
        checkinEnabled: true,
        checkinFrequency: 'QUARTERLY',
        lastCheckinAt: daysAgo(300),
        checkinRemindersSent: REMINDERS_BEFORE_ALERT,
        checkinAlertedAt: null,
        createdAt: daysAgo(400),
      },
      [], // no confirmed trustee
    );

    const res = await new CheckinService(db.prisma, notifs).runDailyCheckins();

    expect(res).toEqual({ reminded: 0, alerted: 1 });
    expect(notifs.sendEmail).not.toHaveBeenCalled();
    expect(db.users[0].checkinAlertedAt).toBeInstanceOf(Date);
  });

  it('one user’s failed notification does not abort the sweep', async () => {
    const notifs = { sendEmail: jest.fn().mockRejectedValue(new Error('smtp down')), sendSms: jest.fn() } as any;
    const db = makeDb({
      id: 'u1',
      email: 'a@x.com',
      phone: null,
      checkinEnabled: true,
      checkinFrequency: 'QUARTERLY',
      lastCheckinAt: daysAgo(200),
      checkinRemindersSent: 0,
      checkinAlertedAt: null,
      createdAt: daysAgo(400),
    });

    await expect(new CheckinService(db.prisma, notifs).runDailyCheckins()).resolves.toEqual({
      reminded: 0,
      alerted: 0,
    });
  });
});
