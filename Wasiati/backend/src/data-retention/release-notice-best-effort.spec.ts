import { DataRetentionService } from './data-retention.service';

/**
 * The release notice is the ONLY thing that tells a family the will is theirs to read, and
 * it goes out AFTER release() has already committed the RELEASED status and the 90-day
 * purge deadline.
 *
 * It used to be `for (const to of recipients) await sendEmail(...)`. One dead address — a
 * typo an heir made two years earlier, an SMTP bounce — threw out of the loop, silenced
 * every recipient after it, and propagated a 500 out of an admin action that had already
 * succeeded. The estate WAS released; the admin saw a failure; the family was never told;
 * and the purge clock ran anyway. Ninety days later the will was gone.
 *
 * And the recipient list itself did not include HEIRS. It read `witnesses` and `trustees`
 * only, so the people the will belongs to were contacted by nothing at all.
 */
function makeService(
  opts: { wills?: any[]; failFor?: string[]; dropFor?: string[]; retentionDays?: string } = {},
) {
  const sent: { to: string; subject: string; body: string }[] = [];
  const prisma: any = {
    user: {
      findUnique: async () => ({ email: 'owner@x.com' }),
      findMany: async () => [],
      update: async () => ({}),
    },
    will: { findMany: async () => opts.wills ?? [] },
  };
  const notifications: any = {
    // Returns the real contract: TRUE means actually dispatched. A double that returned
    // undefined would now (correctly) be counted as undelivered.
    sendEmail: async (to: string, subject: string, body: string) => {
      if (opts.failFor?.includes(to)) throw new Error(`mailbox unavailable: ${to}`);
      if (opts.dropFor?.includes(to)) return false; // transport dropped it, without throwing
      sent.push({ to, subject, body });
      return true;
    },
  };
  const config: any = {
    get: (k: string) =>
      k === 'DATA_RETENTION_DAYS' ? opts.retentionDays : k === 'APP_BASE_URL' ? 'https://app.wasiati.com' : undefined,
  };
  // These suites only exercise the notification paths; storage is never reached.
  return { svc: new DataRetentionService(prisma, config, notifications, unusedStorage(), unusedIdentity()), sent };
}

/** The KYC vendor is only reached by the purge, never by a reminder. */
const unusedIdentity = () =>
  ({
    redactPersonalData: () => {
      throw new Error('the KYC vendor must not be touched while sending reminders');
    },
  }) as any;

/** Storage the reminder paths never touch — any call here is a bug, so it throws. */
const unusedStorage = () =>
  ({
    configured: true,
    purgePrefix: () => {
      throw new Error('storage must not be touched while sending reminders');
    },
  }) as any;

const willWith = (over: any = {}) => ({
  heirContacts: [],
  trustees: [],
  witnesses: [],
  ...over,
});

describe('one throwing recipient does not abort the rest', () => {
  it('delivers to everyone else when the FIRST address fails', async () => {
    const { svc, sent } = makeService({
      wills: [
        willWith({
          heirContacts: [{ email: 'bad@x.com' }, { email: 'heir2@x.com' }],
          trustees: [{ email: 'trustee@x.com' }],
        }),
      ],
      failFor: ['bad@x.com'],
    });

    const delivered = await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));

    expect(delivered).toBe(2);
    expect(sent.map((s) => s.to).sort()).toEqual(['heir2@x.com', 'trustee@x.com']);
  });

  it('does not throw out of sendReleaseNotice even when EVERY address fails', async () => {
    const { svc, sent } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'a@x.com' }, { email: 'b@x.com' }] })],
      failFor: ['a@x.com', 'b@x.com'],
    });
    // release() has already committed by the time this runs. It must not be able to throw.
    await expect(svc.sendReleaseNotice('owner-1', new Date())).resolves.toBe(0);
    expect(sent).toHaveLength(0);
  });

  it('keeps the nightly reminder job running past a bad address', async () => {
    const sent: { to: string }[] = [];
    const updated: string[] = [];
    const purgeAt = new Date(Date.now() + 5 * 86_400_000); // 5 days out -> the "7" milestone
    const prisma: any = {
      user: {
        findMany: async () => [
          { id: 'u1', email: 'owner@x.com', scheduledPurgeAt: purgeAt, retentionRemindersSent: [] },
        ],
        findUnique: async () => ({ email: 'owner@x.com' }),
        update: async ({ where }: any) => updated.push(where.id),
      },
      will: {
        findMany: async () => [
          willWith({ heirContacts: [{ email: 'bad@x.com' }, { email: 'good@x.com' }] }),
        ],
      },
    };
    const notifications: any = {
      sendEmail: async (to: string) => {
        if (to === 'bad@x.com') throw new Error('mailbox unavailable');
        sent.push({ to });
        return true;
      },
    };
    const svc = new DataRetentionService(prisma, { get: () => undefined } as any, notifications, unusedStorage(), unusedIdentity());

    await expect(svc.sendDueReminders()).resolves.toEqual({ remindedAccounts: 1 });
    expect(sent.map((s) => s.to)).toEqual(['good@x.com']);
    // The milestone is still marked. Before the fix the throw happened BEFORE this write,
    // so the account was retried and re-failed every night until the window closed.
    expect(updated).toEqual(['u1']);
  });
});

describe('the release notice reaches HEIRS, and points them at the portal', () => {
  it('includes heir addresses, which the old recipient list dropped entirely', async () => {
    const { svc, sent } = makeService({
      wills: [
        willWith({
          heirContacts: [{ email: 'heir@x.com' }],
          trustees: [{ email: 'trustee@x.com' }],
          witnesses: [{ email: 'witness@x.com' }],
        }),
      ],
    });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));
    expect(sent.map((s) => s.to).sort()).toEqual(['heir@x.com', 'trustee@x.com', 'witness@x.com']);
  });

  it('tells heirs and trustees where to go, with the role prefilled', async () => {
    const { svc, sent } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'heir@x.com' }], trustees: [{ email: 'trustee@x.com' }] })],
    });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));

    const heirMail = sent.find((s) => s.to === 'heir@x.com')!;
    const trusteeMail = sent.find((s) => s.to === 'trustee@x.com')!;
    expect(heirMail.body).toContain('https://app.wasiati.com/portal?role=heir');
    expect(trusteeMail.body).toContain('https://app.wasiati.com/portal?role=trustee');
  });

  /**
   * THE LOAD-BEARING ONE. A release notice gets forwarded — "here is the email about dad's
   * will" — far more often than it gets guarded. A credential in it would hand the entire
   * estate to whoever received the forward. The link grants NOTHING: everyone arrives at the
   * portal and is sent a one-time code to the contact on file.
   */
  it('embeds NO token of any kind', async () => {
    const { svc, sent } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'heir@x.com' }] })],
    });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));

    const body = sent[0].body;
    expect(body).not.toMatch(/\/claim\/[A-Za-z0-9_-]{20,}/); // the claim-submit link shape
    expect(body).not.toMatch(/[A-Za-z0-9_-]{43}/); // a raw 256-bit base64url token
    expect(body).not.toMatch(/token=/i);
    expect(body).toContain('one-time code');
  });

  // The old copy said "Please sign in and download whatever you need". There is no sign-in
  // for these people and there never was — that sentence was the whole of the hand-over.
  it('no longer tells anyone to sign in', async () => {
    const { svc, sent } = makeService({
      wills: [
        willWith({
          heirContacts: [{ email: 'heir@x.com' }],
          trustees: [{ email: 'trustee@x.com' }],
          witnesses: [{ email: 'witness@x.com' }],
        }),
      ],
    });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));
    for (const mail of sent) expect(mail.body).not.toMatch(/sign in/i);
  });

  // A witness attests to the signing and is not a beneficiary; the portal has nothing for
  // them. Sending a link they cannot use is worse than sending none — they would try it and
  // conclude the product is broken at the worst possible moment.
  it('sends a witness a notice with no portal link', async () => {
    const { svc, sent } = makeService({ wills: [willWith({ witnesses: [{ email: 'witness@x.com' }] })] });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));
    expect(sent).toHaveLength(1);
    expect(sent[0].body).not.toContain('/portal');
    expect(sent[0].body).toContain('witness');
  });

  it('emails one person once when they hold two roles', async () => {
    const { svc, sent } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'both@x.com' }], trustees: [{ email: 'BOTH@x.com' }] })],
    });
    await svc.sendReleaseNotice('owner-1', new Date('2026-10-17'));
    expect(sent).toHaveLength(1);
    // Heir wins the tie: it is the role with the most to lose from a missed message.
    expect(sent[0].body).toContain('role=heir');
  });
});

describe('the reached-count is honest about what was actually delivered', () => {
  // sendEmail returns FALSE, without throwing, when no transport is configured. Counting
  // the absence of an exception made an unconfigured mailer look like a clean run:
  // "3/3 recipient(s) reached" while nobody was reached. That matters more here than
  // anywhere else in the product — this notice is what tells a family the will is theirs
  // to read, and it starts the 90-day clock after which the data is destroyed. Silently
  // losing it means the estate is erased by a family that was never told it existed.
  it('does NOT count a message the transport dropped', async () => {
    const { svc } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'reached@x.com' }, { email: 'dropped@x.com' }] })],
      dropFor: ['dropped@x.com'],
    });
    await expect(svc.sendReleaseNotice('owner-1', new Date('2026-10-17'))).resolves.toBe(1);
  });

  it('counts zero when the mail transport is entirely unconfigured', async () => {
    const { svc } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'a@x.com' }, { email: 'b@x.com' }] })],
      dropFor: ['a@x.com', 'b@x.com'],
    });
    await expect(svc.sendReleaseNotice('owner-1', new Date('2026-10-17'))).resolves.toBe(0);
  });

  it('still counts the ones that genuinely went out', async () => {
    const { svc } = makeService({
      wills: [willWith({ heirContacts: [{ email: 'a@x.com' }, { email: 'b@x.com' }] })],
    });
    await expect(svc.sendReleaseNotice('owner-1', new Date('2026-10-17'))).resolves.toBe(2);
  });
});
