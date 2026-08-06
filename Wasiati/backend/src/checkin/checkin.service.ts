import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { CheckinFrequency, ClaimInitPolicy } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CRON_LOCKS, withCronLock } from '../common/cron-lock';

/**
 * Inactivity check-in — a DEATH TRIGGER, not a marketing ping (spec §6).
 *
 * Periodically we ask the user to confirm they are alive. Two unanswered reminders
 * alert their trustee. It is **off by default**: nobody is asked whether they are
 * still living without opting in.
 *
 * Design constraints that shape the code:
 *   · A reminder is only sent when one is actually DUE. The daily job must be safe to
 *     run twice in a day, and safe to run after an outage — it never fires a burst of
 *     back-dated reminders.
 *   · The trustee is alerted ONCE per lapse (`checkinAlertedAt`), not every night.
 *   · Confirming resets everything. A user who answers is fully back to normal.
 *   · An alerted trustee does NOT release anything. It opens a human-reviewed claim
 *     path; approval is a separate, audited action.
 */

/** Two unanswered reminders and the trustee is told. */
export const REMINDERS_BEFORE_ALERT = 2;

/** Gap between reminders once a check-in is overdue. */
export const REMINDER_INTERVAL_DAYS = 14;

const DAY_MS = 24 * 60 * 60 * 1000;

export const FREQUENCY_DAYS: Record<CheckinFrequency, number> = {
  MONTHLY: 30,
  QUARTERLY: 91,
  YEARLY: 365,
};

export interface CheckinState {
  checkinEnabled: boolean;
  checkinFrequency: CheckinFrequency;
  lastCheckinAt: Date | null;
  checkinRemindersSent: number;
  checkinAlertedAt: Date | null;
  createdAt: Date;
}

export type CheckinAction = 'none' | 'remind' | 'alert-trustee';

/**
 * Decides what the daily job should do for one user. Pure, so every branch is
 * testable without a database or a clock.
 */
export function decideCheckinAction(user: CheckinState, now: Date): CheckinAction {
  if (!user.checkinEnabled) return 'none';

  // Never confirmed? The clock starts from sign-up, not from the epoch.
  const anchor = user.lastCheckinAt ?? user.createdAt;
  const dueAt = anchor.getTime() + FREQUENCY_DAYS[user.checkinFrequency] * DAY_MS;
  if (now.getTime() < dueAt) return 'none';

  // Overdue. Have we already exhausted the reminders?
  if (user.checkinRemindersSent >= REMINDERS_BEFORE_ALERT) {
    // Alert the trustee exactly once per lapse.
    return user.checkinAlertedAt ? 'none' : 'alert-trustee';
  }

  // Space the reminders out: the first lands when the check-in falls due, and each
  // subsequent one REMINDER_INTERVAL_DAYS later. Without this the job would send a
  // reminder every single night an account was overdue.
  const nextReminderAt = dueAt + user.checkinRemindersSent * REMINDER_INTERVAL_DAYS * DAY_MS;
  return now.getTime() >= nextReminderAt ? 'remind' : 'none';
}

@Injectable()
export class CheckinService {
  private readonly logger = new Logger(CheckinService.name);

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
  ) {}

  /** The user says: I am still here. Resets the reminder counter and any alert. */
  async confirmAlive(userId: string) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        lastCheckinAt: new Date(),
        checkinRemindersSent: 0,
        checkinAlertedAt: null,
      },
    });
    this.logger.log(`Check-in confirmed by ${userId}.`);
    return { lastCheckinAt: user.lastCheckinAt, checkinRemindersSent: 0 };
  }

  /** Who may report this user's death (spec §6). Enforced in DeathClaimsService. */
  async setClaimInitPolicy(userId: string, claimInitPolicy: ClaimInitPolicy) {
    const user = await this.prisma.user.update({ where: { id: userId }, data: { claimInitPolicy } });
    this.logger.log(`Claim-initiation policy for ${userId} set to ${claimInitPolicy}.`);
    return { claimInitPolicy: user.claimInitPolicy };
  }

  async updateSettings(
    userId: string,
    data: { checkinEnabled?: boolean; checkinFrequency?: CheckinFrequency },
  ) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        ...data,
        // Turning it on (re)starts the clock rather than instantly firing a reminder
        // because the account is years old.
        ...(data.checkinEnabled === true
          ? { lastCheckinAt: new Date(), checkinRemindersSent: 0, checkinAlertedAt: null }
          : {}),
      },
    });
    return {
      checkinEnabled: user.checkinEnabled,
      checkinFrequency: user.checkinFrequency,
      lastCheckinAt: user.lastCheckinAt,
    };
  }

  async status(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    return {
      checkinEnabled: user.checkinEnabled,
      checkinFrequency: user.checkinFrequency,
      lastCheckinAt: user.lastCheckinAt,
      remindersSent: user.checkinRemindersSent,
      trusteeAlerted: !!user.checkinAlertedAt,
      claimInitPolicy: user.claimInitPolicy,
    };
  }

  @Cron(CronExpression.EVERY_DAY_AT_5AM)
  async runDailyCheckinsCron() {
    await withCronLock(this.prisma, CRON_LOCKS.checkinSweep, 'daily-checkins', () => this.runDailyCheckins());
  }

  async runDailyCheckins() {
    const now = new Date();
    const users = await this.prisma.user.findMany({ where: { checkinEnabled: true } });

    let reminded = 0;
    let alerted = 0;

    for (const user of users) {
      const action = decideCheckinAction(user, now);
      if (action === 'none') continue;

      try {
        if (action === 'remind') {
          await this.sendReminder(user.id, user.email, user.phone);
          reminded++;
        } else {
          await this.alertTrustee(user.id, user.email);
          alerted++;
        }
      } catch (e) {
        // One user's failed SMS must not stop everyone else's check-in.
        this.logger.error(`Check-in ${action} failed for ${user.id}: ${(e as Error).message}`);
      }
    }

    if (reminded || alerted) {
      this.logger.log(`Check-in sweep: ${reminded} reminder(s), ${alerted} trustee alert(s).`);
    }
    return { reminded, alerted };
  }

  private async sendReminder(userId: string, email: string, phone: string | null) {
    await this.notifications.sendEmail(
      email,
      'Wasiati — are you still with us?',
      'Please confirm you are well so we do not alert your trustee. If you do not respond to two reminders, your trustee will be notified.',
    );
    if (phone) {
      await this.notifications.sendSms(phone, 'Wasiati check-in: please confirm you are well in the app.');
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { checkinRemindersSent: { increment: 1 } },
    });
  }

  /**
   * Tells the trustee the user has gone quiet. This does NOT release the will and it
   * does NOT declare anyone dead: it opens the human-reviewed claim path.
   */
  private async alertTrustee(userId: string, userEmail: string) {
    const trustees = await this.prisma.trustee.findMany({
      where: { will: { ownerId: userId }, status: 'CONFIRMED' },
    });

    if (trustees.length === 0) {
      // Nobody to tell. Stamp it anyway so we don't retry nightly, and say so loudly.
      await this.prisma.user.update({ where: { id: userId }, data: { checkinAlertedAt: new Date() } });
      this.logger.warn(`User ${userId} missed ${REMINDERS_BEFORE_ALERT} check-ins but has NO confirmed trustee.`);
      return;
    }

    for (const trustee of trustees) {
      if (trustee.email) {
        await this.notifications.sendEmail(
          trustee.email,
          'Wasiati — a check-in was missed',
          `${userEmail} has not responded to their Wasiati check-ins. If you believe they have passed away, you can begin a claim in the app. No will has been released; every claim is reviewed by a person.`,
        );
      }
      if (trustee.phone) {
        await this.notifications.sendSms(
          trustee.phone,
          'Wasiati: a person who named you as trustee has missed their check-ins. Please open the app.',
        );
      }
    }

    await this.prisma.user.update({ where: { id: userId }, data: { checkinAlertedAt: new Date() } });
    this.logger.warn(`Trustee(s) alerted for user ${userId} after ${REMINDERS_BEFORE_ALERT} missed check-ins.`);
  }
}
