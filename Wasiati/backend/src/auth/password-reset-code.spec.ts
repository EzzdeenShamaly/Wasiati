import { BadRequestException } from '@nestjs/common';
import { AccountRecoveryService, PASSWORD_RESET_PURPOSE } from './account-recovery.service';

/**
 * Password reset by one-time CODE rather than an emailed link.
 *
 * The link is a bearer credential: whoever holds that mail — a forwarded thread, a shared
 * family inbox, a synced device — owns the account. A will platform has more shared inboxes
 * than most products. A code has to be typed into the session that requested it, and when
 * the user has a phone the reset moves to a SECOND channel, so owning the mailbox alone is
 * no longer enough. Same posture as login (f242634): a password is never sufficient alone.
 *
 * Two properties matter more than the happy path, and both are pinned here:
 *   1. the endpoint must never reveal whether an account exists;
 *   2. issue and verify must resolve the SAME destination — login MFA and will step-up each
 *      shipped a version of that bug (emailed a code, then checked the phone).
 */
function harness(user: any) {
  const prisma: any = {
    user: { findUnique: jest.fn().mockResolvedValue(user), update: jest.fn().mockResolvedValue(user) },
  };
  const otp: any = {
    issue: jest.fn().mockResolvedValue({ id: 'otp1' }),
    verify: jest.fn().mockResolvedValue(true),
  };
  const tokens: any = { revokeAllForUser: jest.fn().mockResolvedValue(undefined) };
  const mail: any = { enqueue: jest.fn(), sendPasswordReset: jest.fn(), sendVerification: jest.fn() };
  const config: any = { get: () => 'http://localhost:3000' };
  const svc = new AccountRecoveryService(prisma, mail, tokens, config, otp);
  return { svc, prisma, otp, tokens };
}

const withPhone = { id: 'u1', email: 'a@b.test', phone: '+966555000111', passwordHash: 'hash' };
const phoneless = { id: 'u2', email: 'c@d.test', phone: null, passwordHash: 'hash' };
const oauthOnly = { id: 'u3', email: 'e@f.test', phone: null, passwordHash: null };

describe('requesting a reset code', () => {
  it('texts the code when the account has a phone — a second channel, not the mailbox', async () => {
    const { svc, otp } = harness(withPhone);
    await svc.requestPasswordResetCode('a@b.test');
    expect(otp.issue).toHaveBeenCalledWith('+966555000111', PASSWORD_RESET_PURPOSE, 'u1', 'sms');
  });

  it('falls back to email when there is no phone, rather than stranding the account', async () => {
    // `phone` is optional on User. A phone-only implementation would leave every
    // phoneless account unable to recover at all.
    const { svc, otp } = harness(phoneless);
    await svc.requestPasswordResetCode('c@d.test');
    expect(otp.issue).toHaveBeenCalledWith('c@d.test', PASSWORD_RESET_PURPOSE, 'u2', 'email');
  });

  it('answers identically for an unknown address, and sends nothing', async () => {
    const { svc, otp } = harness(null);
    await expect(svc.requestPasswordResetCode('ghost@nowhere.test')).resolves.toEqual({ sent: true });
    expect(otp.issue).not.toHaveBeenCalled();
  });

  it('answers identically for an OAuth-only account, and sends nothing', async () => {
    // No passwordHash means there is no password to reset. Saying so would confirm the
    // address exists AND leak how they sign in.
    const { svc, otp } = harness(oauthOnly);
    await expect(svc.requestPasswordResetCode('e@f.test')).resolves.toEqual({ sent: true });
    expect(otp.issue).not.toHaveBeenCalled();
  });
});

describe('redeeming a reset code', () => {
  it('verifies against the destination the code was ISSUED to', async () => {
    // The bug both login MFA and will step-up shipped: issue to one channel, verify
    // against another, so phoneless accounts were emailed a code and then refused.
    const { svc, otp } = harness(phoneless);
    await svc.resetPasswordWithCode('c@d.test', '123456', 'a-long-enough-password');
    expect(otp.verify).toHaveBeenCalledWith('c@d.test', PASSWORD_RESET_PURPOSE, '123456');
  });

  it('revokes every existing session — a reset must log out the attacker too', async () => {
    const { svc, tokens, prisma } = harness(withPhone);
    await svc.resetPasswordWithCode('a@b.test', '123456', 'a-long-enough-password');
    expect(prisma.user.update).toHaveBeenCalled();
    expect(tokens.revokeAllForUser).toHaveBeenCalledWith('u1');
  });

  it('does not store the new password in plaintext', async () => {
    const { svc, prisma } = harness(withPhone);
    await svc.resetPasswordWithCode('a@b.test', '123456', 'a-long-enough-password');
    const written = prisma.user.update.mock.calls[0][0].data.passwordHash;
    expect(written).not.toBe('a-long-enough-password');
    expect(written).toMatch(/^\$2[aby]\$/); // bcrypt
  });

  it('a wrong code changes nothing', async () => {
    const { svc, otp, prisma, tokens } = harness(withPhone);
    otp.verify.mockResolvedValue(false);
    await expect(svc.resetPasswordWithCode('a@b.test', '000000', 'a-long-enough-password')).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.user.update).not.toHaveBeenCalled();
    expect(tokens.revokeAllForUser).not.toHaveBeenCalled();
  });

  it('every failure reads the same, so this is not an existence oracle', async () => {
    // Unknown address, OAuth-only account, wrong code, expired code, attempts burned —
    // one message. OtpService throws DISTINGUISHABLE errors ("no pending code" vs
    // "expired" vs "too many attempts"), which is precisely what has to be collapsed.
    const messages: string[] = [];

    for (const [user, setup] of [
      [null, () => {}],
      [oauthOnly, () => {}],
      [withPhone, (o: any) => o.verify.mockResolvedValue(false)],
      [withPhone, (o: any) => o.verify.mockRejectedValue(new BadRequestException('Code has expired.'))],
      [withPhone, (o: any) => o.verify.mockRejectedValue(new BadRequestException('Too many incorrect attempts.'))],
    ] as const) {
      const { svc, otp } = harness(user);
      setup(otp);
      await svc.resetPasswordWithCode('a@b.test', '123456', 'a-long-enough-password').catch((e) => {
        messages.push(e.message);
      });
    }

    expect(messages).toHaveLength(5);
    expect(new Set(messages).size).toBe(1);
  });
});
