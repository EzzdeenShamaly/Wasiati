import { BadRequestException, ConflictException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appBaseUrl } from '../common/app-url';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CRON_LOCKS, withCronLock } from '../common/cron-lock';
import { STORAGE_PROVIDER, StorageProviderPort } from '../files/storage-provider.interface';
import { UPLOAD_PREFIXES } from '../files/files.service';
import { IdentityService } from '../identity/identity.service';
import { IdVerificationProvider } from '@prisma/client';

/**
 * Who asked for a purge and, if the released-claim precondition is being
 * overridden, the typed confirmation + reason that make the override deliberate
 * and attributable. Absent entirely for the daily cron (actorRole SYSTEM).
 */
export interface PurgeContext {
  actorId: string;
  overrideConfirmation?: string;
  reason?: string;
}

// Days-remaining marks at which we email the witnesses/trustees to download before
// deletion. (The initial "you have N days" notice is sent at release, separately.)
const REMINDER_THRESHOLDS = [30, 7, 3];

/**
 * Posthumous data retention. When a death claim is released, the deceased's account
 * is stamped with scheduledPurgeAt = now + DATA_RETENTION_DAYS (default 90). This job
 * runs daily and HARD-DELETES every piece of that person's data once the window
 * passes, leaving only an anonymized DataPurgeLog tombstone for compliance.
 *
 * The 90-day window is the heirs' access period: after the will is released they have
 * that long to retrieve everything before it's erased for good.
 */
@Injectable()
export class DataRetentionService {
  private readonly logger = new Logger(DataRetentionService.name);

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    private notifications: NotificationsService,
    @Inject(STORAGE_PROVIDER) private storage: StorageProviderPort,
    private identity: IdentityService,
  ) {}

  retentionDays(): number {
    const n = Number(this.config.get<string>('DATA_RETENTION_DAYS'));
    return Number.isFinite(n) && n > 0 ? n : 90;
  }

  /** Marks a user for purge N days from now (called when their will is released). */
  purgeDeadline(from: Date = new Date()): Date {
    return new Date(from.getTime() + this.retentionDays() * 24 * 60 * 60 * 1000);
  }

  /**
   * Given days remaining and the milestones already sent, returns the most-urgent
   * unsent milestone that is now due (or null). Pure + deterministic — unit-tested.
   */
  static pickDueReminder(daysRemaining: number, sent: string[], thresholds = REMINDER_THRESHOLDS): number | null {
    const passed = thresholds.filter((t) => daysRemaining <= t);
    const unsent = passed.filter((t) => !sent.includes(String(t)));
    return unsent.length ? Math.min(...unsent) : null;
  }

  // --- retention reminder emails -------------------------------------------

  /**
   * Distinct people to notify across all of a user's wills, each with the role that
   * decides what we can honestly tell them.
   *
   * HEIRS ARE INCLUDED, and were not before. This list drove every posthumous notice in
   * the product, and it read only `witnesses` and `trustees` — so the people the will
   * actually belongs to were contacted by NOTHING at release and NOTHING as the purge
   * clock ran down. They now come first in the dedupe order, because heir is the role
   * with the most to lose from a missed message.
   *
   * Deduped by address: one person listed twice (an heir who is also the trustee) gets one
   * email, under the first role in that order.
   */
  private async recipientsForUser(userId: string): Promise<{ email: string; role: 'heir' | 'trustee' | 'witness' }[]> {
    const wills = await this.prisma.will.findMany({
      where: { ownerId: userId },
      select: {
        heirContacts: { select: { email: true } },
        trustees: { select: { email: true } },
        witnesses: { select: { email: true } },
      },
    });
    const byEmail = new Map<string, 'heir' | 'trustee' | 'witness'>();
    const add = (email: string | null, role: 'heir' | 'trustee' | 'witness') => {
      if (!email) return;
      const key = email.toLowerCase();
      if (!byEmail.has(key)) byEmail.set(key, role);
    };
    for (const w of wills) {
      for (const h of w.heirContacts) add(h.email, 'heir');
      for (const t of w.trustees) add(t.email, 'trustee');
      for (const wit of w.witnesses) add(wit.email, 'witness');
    }
    return [...byEmail].map(([email, role]) => ({ email, role }));
  }

  /** Where a recipient goes to read what was released to them. */
  private portalLink(role: 'heir' | 'trustee' | 'witness'): string | null {
    // A witness attests to the signing; they are not a beneficiary and the portal has
    // nothing for them. Sending them a link they cannot use would be worse than sending
    // none — they would try it and conclude the system is broken.
    if (role === 'witness') return null;
    const base = appBaseUrl(this.config);
    // The role is PREFILLED FOR CONVENIENCE AND GRANTS NOTHING. Everyone still arrives at
    // the same email → one-time code sign-in. Compare the claim-submit link, which carries
    // a credential in the path: this one deliberately does not, because a release notice is
    // forwarded ("here's the email about dad's will") far more often than it is guarded,
    // and a token in it would hand the whole estate to whoever it was forwarded to.
    return `${base}/portal?role=${role}`;
  }

  private reminderCopy(
    kind: 'initial' | '30' | '7' | '3',
    ownerEmail: string,
    deadline: Date,
    totalDays: number,
    role: 'heir' | 'trustee' | 'witness',
  ) {
    const by = deadline.toISOString().slice(0, 10);
    const link = this.portalLink(role);
    // Two shapes, because there are two truths. A heir/trustee has somewhere to go; a
    // witness has only the fact that the will was released and the records will go.
    // "Sign in" is the exact phrase this copy is being rewritten to remove. These people
    // have no account and never will — telling them to sign in sent them looking for a
    // password that does not exist. They enter their address and receive a one-time code.
    const where = link
      ? `Open the heir & trustee portal at ${link}, enter this email address, and we will send you a one-time code. `
      : '';
    switch (kind) {
      case 'initial':
        return {
          subject: `A will you are named on has been released — available for ${totalDays} days`,
          body: link
            ? `The will for ${ownerEmail} has been released. ${where}Everything released to you remains available until ${by} (${totalDays} days), after which it is permanently deleted.`
            : `The will for ${ownerEmail} has been released. You are named on it as a witness. The records are permanently deleted on ${by} (${totalDays} days from now). If you need anything from them before that, please contact us.`,
        };
      case '30':
        return {
          subject: 'About 30 days left to read the will',
          body: `Reminder: the will and documents for ${ownerEmail} will be permanently deleted on ${by}. About 30 days remain. ${where}`.trim(),
        };
      case '7':
        return {
          subject: 'One week left to read the will',
          body: `The will and documents for ${ownerEmail} will be permanently deleted on ${by} — about a week from now. ${where}`.trim(),
        };
      case '3':
        return {
          subject: 'Final notice: about 3 days until permanent deletion',
          body: `Final reminder: the will and all documents for ${ownerEmail} will be permanently deleted on ${by}, in about 3 days. ${where}This cannot be undone.`.trim(),
        };
    }
  }

  /**
   * Best-effort per recipient. One bad address MUST NOT abort the loop: this runs after
   * release() has already committed the RELEASED status and the purge deadline, so an
   * exception escaping here unwinds nothing — it just propagates a 500 out of an admin
   * action that already succeeded, and silences every recipient after the bad one.
   */
  private async sendEach(
    recipients: { email: string; role: 'heir' | 'trustee' | 'witness' }[],
    copy: (role: 'heir' | 'trustee' | 'witness') => { subject: string; body: string },
  ): Promise<number> {
    let sent = 0;
    for (const r of recipients) {
      try {
        const { subject, body } = copy(r.role);
        // sendEmail reports whether it actually DISPATCHED, and returns false without
        // throwing when no transport is configured. Counting the absence of an exception
        // made an unconfigured mailer look like a clean run: "3/3 recipient(s) reached"
        // when nobody was reached. This is the notice that tells a family the will was
        // released and starts their 90-day clock — the one message that must not be
        // quietly lost, because the data is destroyed when that clock runs out.
        if (await this.notifications.sendEmail(r.email, subject, body)) {
          sent++;
        } else {
          this.logger.error(`A retention notice to a ${r.role} was NOT delivered — the mail transport dropped it.`);
        }
      } catch (e) {
        // The address is PII; log the role and the failure, not who.
        this.logger.error(`Could not send a retention notice to a ${r.role}: ${(e as Error).message}`);
      }
    }
    return sent;
  }

  /** Sends the initial "you have N days" notice to the heirs/trustees/witnesses at release. */
  async sendReleaseNotice(ownerId: string, deadline: Date) {
    const owner = await this.prisma.user.findUnique({ where: { id: ownerId }, select: { email: true } });
    const recipients = await this.recipientsForUser(ownerId);
    const ownerEmail = owner?.email ?? 'the deceased';
    const sent = await this.sendEach(recipients, (role) =>
      this.reminderCopy('initial', ownerEmail, deadline, this.retentionDays(), role),
    );
    this.logger.log(
      `Release notice: ${sent}/${recipients.length} recipient(s) reached for user ${ownerId}.`,
    );
    return sent;
  }

  /** Daily: emails the 30/7/3-day-remaining reminders, each exactly once. */
  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async sendDueRemindersCron() {
    await withCronLock(this.prisma, CRON_LOCKS.retentionNotices, 'retention-reminders', () => this.sendDueReminders());
  }

  async sendDueReminders() {
    const users = await this.prisma.user.findMany({
      // A held estate keeps its scheduledPurgeAt but will NOT be purged, so counting down
      // to it tells the heirs something untrue — "3 days to retrieve everything" for a
      // deadline that will never arrive. Worse, sending marks the milestone spent, so if
      // the hold is later released the real countdown can never be re-announced.
      where: { scheduledPurgeAt: { gt: new Date() }, legalHoldAt: null },
      select: { id: true, email: true, scheduledPurgeAt: true, retentionRemindersSent: true },
    });
    let sentCount = 0;
    for (const u of users) {
      const daysRemaining = Math.ceil((u.scheduledPurgeAt!.getTime() - Date.now()) / 86_400_000);
      const due = DataRetentionService.pickDueReminder(daysRemaining, u.retentionRemindersSent);
      if (due == null) continue;
      const recipients = await this.recipientsForUser(u.id);
      // Per-recipient try/catch, same reason as sendReleaseNotice: this is a nightly cron
      // over EVERY account in its retention window, so one unmailable address used to abort
      // the whole night's run — and because the milestone is only marked after the loop,
      // the accounts behind it would be retried and re-failed every night until the window
      // closed and their heirs were never told.
      await this.sendEach(recipients, (role) =>
        this.reminderCopy(String(due) as '30' | '7' | '3', u.email, u.scheduledPurgeAt!, this.retentionDays(), role),
      );
      // Mark every milestone already passed as sent, so a less-urgent one never fires late.
      const passed = REMINDER_THRESHOLDS.filter((t) => daysRemaining <= t).map(String);
      const merged = [...new Set([...u.retentionRemindersSent, ...passed])];
      await this.prisma.user.update({ where: { id: u.id }, data: { retentionRemindersSent: merged } });
      sentCount++;
    }
    if (sentCount) this.logger.log(`Retention reminders sent for ${sentCount} account(s).`);
    return { remindedAccounts: sentCount };
  }

  // --- reconciliation --------------------------------------------------------

  /**
   * Days a purge may be overdue before it counts as STUCK.
   *
   * runDailyPurge runs once a day, so one missed day is a single failure and possibly
   * transient (a Stripe timeout, a slow S3 sweep). Two consecutive failures is a pattern,
   * and a pattern nobody is told about is the actual problem here.
   */
  private static readonly PURGE_OVERDUE_GRACE_DAYS = 2;

  /**
   * Asks the question nothing else asks: did the work we PROMISED actually happen?
   *
   * runDailyPurge catches a per-user failure, logs it, and moves on — which is right for
   * the batch (one bad record must not halt the others) and wrong for the estate, because
   * nothing escalates. The same account can fail every night for months and the only trace
   * is one line per night in a log nobody reads. That is the shape of every bug found in
   * this codebase this week: the failure is visible exactly once, in a place no one looks.
   *
   * A user row that still EXISTS past its purge date is the whole signal — purgeUser
   * deletes the row, so survival is proof the purge did not complete. Legal holds are
   * excluded because for them not purging is correct.
   *
   * Deliberately read-only. It fixes nothing and retries nothing; it makes the state
   * loud. Repair belongs to the purge itself, which will try again tonight.
   */
  async reconcile(now: Date = new Date()): Promise<{
    purgesOverdue: number;
    noticesOverdue: number;
    heldEstates: number;
    overdueUserIds: string[];
    missedNoticeUserIds: string[];
  }> {
    const cutoff = new Date(now.getTime() - DataRetentionService.PURGE_OVERDUE_GRACE_DAYS * 86_400_000);

    const [overdue, inWindow, heldEstates] = await Promise.all([
      this.prisma.user.findMany({
        where: { scheduledPurgeAt: { not: null, lt: cutoff }, legalHoldAt: null },
        select: { id: true, scheduledPurgeAt: true },
        // Bounded: the point is to raise an alarm, not to page a full table of ids.
        take: 50,
      }),
      // Everyone still inside their retention window — the population sendDueReminders
      // is responsible for. Same filter it uses, so the two agree on who is owed a notice.
      this.prisma.user.findMany({
        where: { scheduledPurgeAt: { gt: now }, legalHoldAt: null },
        select: { id: true, scheduledPurgeAt: true, retentionRemindersSent: true },
      }),
      this.prisma.user.count({ where: { legalHoldAt: { not: null } } }),
    ]);

    // The second half: was every notice we OWED actually sent?
    //
    // sendDueReminders marks every passed threshold as sent, so "a threshold the account
    // is past that is not recorded" means the notice job did not run, or died before the
    // update. Strictly-less-than gives a full day of slack, so the 2am cron and this 4am
    // check never disagree over a same-day boundary or a Math.ceil rounding edge.
    const missedNotices = inWindow.filter((u) => {
      const daysRemaining = Math.ceil((u.scheduledPurgeAt!.getTime() - now.getTime()) / 86_400_000);
      return REMINDER_THRESHOLDS.some((t) => daysRemaining < t && !u.retentionRemindersSent.includes(String(t)));
    });

    if (overdue.length) {
      // ERROR, not warn. This means data we told a family was destroyed is still here,
      // which is a broken promise and — under PDPL, where the deceased are in scope — a
      // missed statutory duty rather than an untidy queue.
      this.logger.error(
        `RETENTION RECONCILE: ${overdue.length} account(s) past their purge date by more than ` +
          `${DataRetentionService.PURGE_OVERDUE_GRACE_DAYS} days and NOT under legal hold. ` +
          `The nightly purge is failing for: ${overdue.map((u) => u.id).join(', ')}`,
      );
    }
    if (missedNotices.length) {
      // Also ERROR: the heirs' 90-day window is only meaningful if they are TOLD about it.
      // A missed notice is a window quietly running out on people who never knew it started.
      this.logger.error(
        `RETENTION RECONCILE: ${missedNotices.length} account(s) are past a 30/7/3-day reminder ` +
          `milestone with no record of it being sent — the reminder cron is not completing for: ` +
          `${missedNotices.slice(0, 50).map((u) => u.id).join(', ')}`,
      );
    }
    if (heldEstates) {
      // Not a fault — a hold is deliberate. But a hold nobody revisits keeps an estate
      // alive indefinitely, so it should be seen rather than silently persist.
      this.logger.warn(`RETENTION RECONCILE: ${heldEstates} estate(s) under legal hold (purge suspended).`);
    }

    return {
      purgesOverdue: overdue.length,
      noticesOverdue: missedNotices.length,
      heldEstates,
      overdueUserIds: overdue.map((u) => u.id),
      missedNoticeUserIds: missedNotices.slice(0, 50).map((u) => u.id),
    };
  }

  @Cron(CronExpression.EVERY_DAY_AT_4AM)
  async reconcileCron() {
    // An hour after the purge (3am) so it grades that run rather than racing it.
    await withCronLock(this.prisma, CRON_LOCKS.retentionReconcile, 'retention-reconcile', () => this.reconcile());
  }

  // --- legal hold ------------------------------------------------------------

  /**
   * Suspends the posthumous purge for one estate, indefinitely.
   *
   * A contested will, a probate dispute, or any preservation obligation makes the
   * automated purge the wrong behaviour: it would destroy the very instrument being
   * litigated, on schedule, with a tombstone recording that we meant to. Nothing could
   * stop it before this. A hold outranks scheduledPurgeAt and is released only by an
   * explicit admin action.
   */
  async placeLegalHold(userId: string, actorId: string, reason: string) {
    const trimmed = (reason ?? '').trim();
    // A hold with no stated reason is unreviewable later — and "why was this estate
    // preserved for three years?" is exactly the question that gets asked.
    if (trimmed.length < 10) {
      throw new BadRequestException('A legal hold needs a reason (at least 10 characters) for the audit trail.');
    }
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { legalHoldAt: true } });
    if (!user) throw new NotFoundException('User not found.');
    if (user.legalHoldAt) throw new ConflictException('This estate is already under legal hold.');

    await this.prisma.user.update({
      where: { id: userId },
      data: { legalHoldAt: new Date(), legalHoldReason: trimmed, legalHoldBy: actorId },
    });
    this.logger.warn(`LEGAL HOLD placed on ${userId} by ${actorId}: ${trimmed}`);
    return { userId, held: true };
  }

  /** Lifts a hold, letting the normal retention schedule resume. */
  async releaseLegalHold(userId: string, actorId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { legalHoldAt: true } });
    if (!user) throw new NotFoundException('User not found.');
    if (!user.legalHoldAt) throw new ConflictException('This estate is not under legal hold.');

    await this.prisma.user.update({
      where: { id: userId },
      data: { legalHoldAt: null, legalHoldReason: null, legalHoldBy: null },
    });
    // Deliberately loud: releasing a hold re-arms an irreversible destruction job.
    this.logger.warn(`LEGAL HOLD RELEASED on ${userId} by ${actorId} — the purge can now run.`);
    return { userId, held: false };
  }

  /** Ops/testing: set a user's purge date N days out and reset reminder tracking. */
  async schedulePurge(userId: string, days: number) {
    const scheduledPurgeAt = new Date(Date.now() + days * 86_400_000);
    await this.prisma.user.update({
      where: { id: userId },
      data: { scheduledPurgeAt, retentionRemindersSent: [] },
    });
    return { userId, scheduledPurgeAt };
  }

  /**
   * Sweeps spent login challenges (backend/src/auth — the proof-of-password behind
   * POST /auth/login/resend-mfa).
   *
   * Hourly, not daily: the TTL is 15 minutes, every password login mints one, and nothing
   * else ever deletes them, so a daily sweep would leave a day of dead credentials sitting
   * in the table. They are inert once expired — resendLoginMfa checks expiresAt, it does not
   * trust the row's existence — but a hashed bearer credential that has stopped being useful
   * should stop being stored.
   */
  // Deliberately UNLOCKED: a single idempotent deleteMany — two instances racing it
  // delete the same expired rows once between them. Not worth a lock's round trip.
  @Cron(CronExpression.EVERY_HOUR)
  async purgeExpiredLoginChallenges() {
    const { count } = await this.prisma.loginChallenge.deleteMany({
      where: { expiresAt: { lt: new Date() } },
    });
    if (count) this.logger.log(`Swept ${count} expired login challenge(s).`);
    return { deleted: count };
  }

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async runDailyPurgeCron() {
    await withCronLock(this.prisma, CRON_LOCKS.retentionPurge, 'retention-purge', () => this.runDailyPurge());
  }

  async runDailyPurge() {
    const due = await this.prisma.user.findMany({
      // An estate under legal hold is skipped silently and indefinitely — not retried
      // and logged as a failure every night. purgeUser guards it again for the admin
      // path, which does not come through here.
      where: { scheduledPurgeAt: { not: null, lte: new Date() }, legalHoldAt: null },
      select: { id: true },
    });
    if (due.length === 0) return;
    this.logger.log(`Posthumous purge: ${due.length} account(s) past retention window.`);
    for (const u of due) {
      try {
        await this.purgeUser(u.id);
      } catch (err) {
        // Don't let one bad record halt the batch; surface it for investigation.
        this.logger.error(`Failed to purge user ${u.id}: ${(err as Error).message}`);
      }
    }
  }

  /**
   * PERMANENTLY erases every stored object belonging to the deceased, and verifies it.
   *
   * Swept by PREFIX rather than by the FileObject rows: an upload that was presigned and
   * PUT but never confirmed has no row, and an unconfirmed id document or death
   * certificate is exactly as sensitive as a confirmed one. The recorded keys are used
   * only as a cross-check in the evidence.
   *
   * Throws unless every prefix verified empty — purgeUser depends on that to guarantee
   * the tombstone is never written over surviving bytes.
   */
  private async eraseStoredObjects(userId: string, recordedKeys: string[]) {
    if (!this.storage.configured) {
      // No bucket at all. Honest only while nothing is recorded — if rows exist, storage
      // was misconfigured out from under real objects and erasing is impossible here.
      if (recordedKeys.length) {
        throw new Error(
          `refusing to purge ${userId}: ${recordedKeys.length} file(s) recorded but storage is not configured`,
        );
      }
      return { method: 'none', prefixes: [], objectsDeleted: 0, versionsDeleted: 0, deleteMarkersDeleted: 0, recordedKeys: 0, verifiedEmptyAt: new Date().toISOString() };
    }

    let method = 'versions';
    let objectsDeleted = 0;
    let versionsDeleted = 0;
    let deleteMarkersDeleted = 0;
    const swept: string[] = [];

    for (const prefix of UPLOAD_PREFIXES) {
      const scope = `${prefix}/${userId}/`;
      const res = await this.storage.purgePrefix(scope);
      if (!res.verifiedEmpty) {
        // Abort BEFORE the database transaction: nothing has been deleted from the DB,
        // scheduledPurgeAt survives, and tonight's failure is simply retried tomorrow.
        throw new Error(`storage erasure could not be verified for ${scope} — aborting purge of ${userId}`);
      }
      method = res.method;
      objectsDeleted += res.objectsDeleted;
      versionsDeleted += res.versionsDeleted;
      deleteMarkersDeleted += res.deleteMarkersDeleted;
      swept.push(scope);
    }

    return {
      method,
      prefixes: swept,
      objectsDeleted,
      versionsDeleted,
      deleteMarkersDeleted,
      // Counts and prefixes only — never the key list. Keys carry nothing but the userId
      // (already on the tombstone) and a uuid, so listing them adds bulk, not evidence.
      recordedKeys: recordedKeys.length,
      verifiedEmptyAt: new Date().toISOString(),
    };
  }

  /**
   * Irreversibly redacts the KYC vendor's copy of this person's identity documents.
   *
   * The government-ID scan and the selfie are the most sensitive artefacts the product
   * ever handles, and they are NOT in our bucket — the vendor holds them, for years, on
   * its own schedule. Erasing our storage while leaving those behind would make the
   * tombstone false exactly where it matters most.
   */
  private async redactIdentityDocuments(userId: string, rail: IdVerificationProvider | null) {
    const result = await this.identity.redactPersonalData(userId);
    // Verified on the document rail, but the configured adapter cannot redact: the ID
    // scan would outlive the purge. Abort before the transaction — same discipline as an
    // unverifiable storage sweep — so a correctly-configured run can do it properly.
    if (rail === IdVerificationProvider.DOCUMENT && !result.supported) {
      throw new Error(
        `refusing to purge ${userId}: verified on the document rail but ${result.provider} cannot redact — ` +
          'the identity documents would survive the purge',
      );
    }
    return result;
  }

  /**
   * Hard-deletes everything belonging to one deceased user, children before parents,
   * in a single transaction. A deceased person may also be a *trustee* on someone
   * else's (living) will — those rows are unlinked (userId -> null), never deleted.
   *
   * ORDER MATTERS, and it is: erase the STORED OBJECTS first, verify, and only then run
   * the database transaction that removes the rows and writes the tombstone.
   *
   * The reverse — which this code used to do, minus any storage step at all — cannot be
   * made safe. `scheduledPurgeAt` on the user row IS the retry intent: runDailyPurge
   * re-selects by it every night. Delete the user first and a crash before the object
   * sweep leaves no row to retry, no tombstone, and bytes stranded in storage with their
   * FileObject references already cascade-deleted — a silent, permanent compliance
   * failure findable only by scanning the bucket. Erasing first inverts every failure
   * into a harmless retry, and makes "tombstone exists" imply "erasure was verified".
   */
  async purgeUser(userId: string) {
    const willIds = (
      await this.prisma.will.findMany({ where: { ownerId: userId }, select: { id: true } })
    ).map((w) => w.id);
    const vault = await this.prisma.vault.findUnique({ where: { userId }, select: { id: true } });
    // Read BEFORE the transaction: FileObject cascades on user delete (schema.prisma),
    // so after the commit the keys are gone and nothing knows what to erase.
    const recordedKeys = (
      await this.prisma.fileObject.findMany({ where: { userId }, select: { key: true } })
    ).map((f) => f.key);
    const owner = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { idVerificationProvider: true, legalHoldAt: true, legalHoldReason: true },
    });
    // Checked HERE and not only in the nightly query, because the admin "purge this
    // account now" endpoint bypasses that query entirely — and a one-click irreversible
    // destruction of evidence under preservation is precisely what must not be possible.
    if (owner?.legalHoldAt) {
      throw new ConflictException(
        `This estate is under legal hold and cannot be purged: ${owner.legalHoldReason ?? 'no reason recorded'}`,
      );
    }

    // Both external erasures run BEFORE the transaction, and both abort it on failure.
    const storage = await this.eraseStoredObjects(userId, recordedKeys);
    const identity = await this.redactIdentityDocuments(userId, owner?.idVerificationProvider ?? null);

    const counts: Record<string, number> = {};
    const n = (k: string, r: { count: number }) => (counts[k] = r.count);

    await this.prisma.$transaction(async (tx) => {
      // 1. children of the deceased's own wills
      if (willIds.length) {
        const w = { willId: { in: willIds } };
        n('assets', await tx.asset.deleteMany({ where: w }));
        n('bequests', await tx.bequest.deleteMany({ where: w }));
        n('shariaShares', await tx.shariaShare.deleteMany({ where: w }));
        n('witnesses', await tx.witness.deleteMany({ where: w }));
        n('trusteesOnOwnWills', await tx.trustee.deleteMany({ where: w }));
        n('deathClaims', await tx.deathClaim.deleteMany({ where: w }));
        n('wills', await tx.will.deleteMany({ where: { id: { in: willIds } } }));
      }
      // 2. deceased as a trustee on OTHER people's wills -> unlink, don't delete
      n('trusteeshipsUnlinked', await tx.trustee.updateMany({ where: { userId }, data: { userId: null } }));
      // 3. vault + items
      if (vault) {
        n('vaultItems', await tx.vaultItem.deleteMany({ where: { vaultId: vault.id } }));
        await tx.vault.delete({ where: { userId } });
        counts['vault'] = 1;
      }
      // 4. everything else directly linked to the user
      n('subscriptions', await tx.subscription.deleteMany({ where: { userId } }));
      n('burialPlans', await tx.burialPrepaymentPlan.deleteMany({ where: { userId } }));
      n('burialEstimates', await tx.burialEstimateRequest.deleteMany({ where: { userId } }));
      n('intakeSessions', await tx.intakeSession.deleteMany({ where: { userId } }));
      n('nafathVerifications', await tx.nafathVerification.deleteMany({ where: { userId } }));
      n('passkeys', await tx.passkeyCredential.deleteMany({ where: { userId } }));
      n('refreshTokens', await tx.refreshToken.deleteMany({ where: { userId } }));
      n('emailVerifications', await tx.emailVerificationToken.deleteMany({ where: { userId } }));
      n('passwordResets', await tx.passwordResetToken.deleteMany({ where: { userId } }));
      n('loginChallenges', await tx.loginChallenge.deleteMany({ where: { userId } }));
      n('otpCodes', await tx.otpCode.deleteMany({ where: { userId } }));
      // File rows, deleted EXPLICITLY rather than by the onDelete: Cascade on user —
      // a cascaded row is invisible to this counter, so the tombstone used to claim a
      // purge without ever accounting for the documents it was mostly about.
      n('fileObjects', await tx.fileObject.deleteMany({ where: { userId } }));
      // 5. finally the user record itself
      await tx.user.delete({ where: { id: userId } });
      counts['user'] = 1;
      // 6. anonymized tombstone (no PII) — carrying the STORAGE ERASURE EVIDENCE, so the
      // claim "permanently deleted" is backed by counts and a verification timestamp
      // rather than by the mere absence of an exception. eraseStoredObjects has already
      // thrown if anything survived, so reaching here means it was verified empty.
      await tx.dataPurgeLog.create({
        data: { deceasedUserId: userId, recordsDeleted: { ...counts, storage, identity } },
      });
    });

    this.logger.log(
      `Purged all data for deceased user ${userId}: ${JSON.stringify(counts)}; ` +
        `storage erased via '${storage.method}' (${storage.objectsDeleted} object(s), ${storage.versionsDeleted} version(s)).`,
    );
    return counts;
  }
}
