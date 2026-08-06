import { BadRequestException, HttpException } from '@nestjs/common';
import { AuthService, PHONE_VERIFY_PURPOSE, LOGIN_MFA_PURPOSE } from './auth.service';
import { TotpService } from './totp.service';

/**
 * Proving the phone given at signup.
 *
 * The number was required at signup but nothing proved it, so a typo sat on the account
 * looking exactly like a good number. That matters more than a wrong email would: this
 * number carries the login second factor, the witness and trustee invitations, and the
 * death-claim lookup — so the mistake stays silent until the will is being executed and the
 * people who have to act cannot be reached.
 */
describe('AuthService — signup phone verification', () => {
  const USER = 'user-1';
  const PHONE = '+14155550123';

  const setup = (over: { phone?: string | null; phoneVerifiedAt?: Date | null; recentAt?: Date; countThisHour?: number } = {}) => {
    const user = {
      id: USER,
      phone: over.phone === undefined ? PHONE : over.phone,
      phoneVerifiedAt: over.phoneVerifiedAt ?? null,
    };
    const prisma = {
      user: { findUnique: jest.fn().mockResolvedValue(user), update: jest.fn().mockResolvedValue(user) },
      otpCode: {
        findFirst: jest.fn().mockResolvedValue(over.recentAt ? { createdAt: over.recentAt } : null),
        count: jest.fn().mockResolvedValue(over.countThisHour ?? 0),
      },
    } as any;
    const otp = { issue: jest.fn().mockResolvedValue('123456'), verify: jest.fn().mockResolvedValue(true) } as any;
    const service = new AuthService(prisma, otp, {} as any, {} as any, new TotpService({ get: () => 'x'.repeat(48) } as any), { consume: async () => false, status: async () => ({ remaining: 0, total: 0, low: false }) } as any);
    return { service, prisma, otp };
  };

  describe('sending the code', () => {
    it('texts the number ALREADY on the account', async () => {
      const { service, otp } = setup();
      await expect(service.sendPhoneVerification(USER)).resolves.toEqual({ sent: true });
      expect(otp.issue).toHaveBeenCalledWith(PHONE, PHONE_VERIFY_PURPOSE, USER, 'sms');
    });

    it('uses a purpose SEPARATE from the login factor', async () => {
      // Sharing one bucket would let a signup verification eat the login allowance, so a
      // user who mistyped their number once could be locked out of signing in.
      const { service, otp } = setup();
      await service.sendPhoneVerification(USER);
      expect(otp.issue.mock.calls[0][1]).toBe(PHONE_VERIFY_PURPOSE);
      expect(otp.issue.mock.calls[0][1]).not.toBe(LOGIN_MFA_PURPOSE);
    });

    it('refuses when the account has no number at all', async () => {
      const { service } = setup({ phone: null });
      await expect(service.sendPhoneVerification(USER)).rejects.toBeInstanceOf(BadRequestException);
    });

    it('is a no-op once the number is already proved', async () => {
      // Idempotent rather than an error: a client retrying after a dropped response should
      // not be told something is wrong.
      const { service, otp } = setup({ phoneVerifiedAt: new Date() });
      await expect(service.sendPhoneVerification(USER)).resolves.toEqual({ sent: true });
      expect(otp.issue).not.toHaveBeenCalled();
    });

    it('429s inside the cooldown instead of silently sending nothing', async () => {
      const { service, otp } = setup({ recentAt: new Date() });
      await expect(service.sendPhoneVerification(USER)).rejects.toBeInstanceOf(HttpException);
      expect(otp.issue).not.toHaveBeenCalled();
    });

    it('429s once the hourly cap is reached', async () => {
      // A toll-fraud brake: every send costs money.
      const { service, otp } = setup({ countThisHour: 5 });
      await expect(service.sendPhoneVerification(USER)).rejects.toBeInstanceOf(HttpException);
      expect(otp.issue).not.toHaveBeenCalled();
    });
  });

  describe('confirming the code', () => {
    it('stamps phoneVerifiedAt on a correct code', async () => {
      const { service, prisma } = setup();
      await expect(service.confirmPhoneVerification(USER, '123456')).resolves.toEqual({ verified: true });
      expect(prisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { phoneVerifiedAt: expect.any(Date) } }),
      );
    });

    it('rejects a wrong code and leaves the account unverified', async () => {
      const { service, prisma, otp } = setup();
      otp.verify.mockResolvedValue(false);
      await expect(service.confirmPhoneVerification(USER, '000000')).rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('verifies against the phone-verify bucket, not the login one', async () => {
      const { service, otp } = setup();
      await service.confirmPhoneVerification(USER, '123456');
      expect(otp.verify).toHaveBeenCalledWith(PHONE, PHONE_VERIFY_PURPOSE, '123456');
    });

    it('replays idempotently once verified, without consuming another code', async () => {
      const { service, otp } = setup({ phoneVerifiedAt: new Date() });
      await expect(service.confirmPhoneVerification(USER, '123456')).resolves.toEqual({ verified: true });
      expect(otp.verify).not.toHaveBeenCalled();
    });
  });
});
