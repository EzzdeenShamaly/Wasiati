import { NotFoundException } from '@nestjs/common';
import { TrusteesService } from './trustees.service';

/**
 * POST /trustees/:trusteeId/send-code is UNAUTHENTICATED; the SMS OTP is the
 * possession factor. The leak was the response echoing that live confirmation code
 * (via devEchoCode when OTP_DEV_ECHO=true), so any anonymous caller who knew a
 * trustee id obtained a code good for TrusteesService.confirm. It must go out only
 * over SMS.
 */
describe('TrusteesService.sendConfirmationCode — no live-OTP echo on the public endpoint', () => {
  it('never returns the OTP in the response, even when OTP echo is active', async () => {
    const prisma: any = {
      trustee: { findUnique: async () => ({ id: 't1', phone: '+100' }) },
    };
    const otp: any = {
      issue: jest.fn().mockResolvedValue('352706'),
      devEchoCode: jest.fn((c: string) => c),
    };
    const svc = new TrusteesService(prisma, otp, { sendSms: jest.fn() } as any, { get: jest.fn() } as any, { incrWithTtl: async () => 1 } as any);

    const res = await svc.sendConfirmationCode('t1');

    expect(res).toEqual({ sent: true });
    expect(res).not.toHaveProperty('devCode');
    expect(otp.issue).toHaveBeenCalledWith('+100', 'trustee_confirm');
    expect(otp.devEchoCode).not.toHaveBeenCalled();
  });

  it('404s an unknown trustee id', async () => {
    const prisma: any = { trustee: { findUnique: async () => null } };
    const svc = new TrusteesService(prisma, { issue: jest.fn() } as any, { sendSms: jest.fn() } as any, { get: jest.fn() } as any, { incrWithTtl: async () => 1 } as any);
    await expect(svc.sendConfirmationCode('nope')).rejects.toBeInstanceOf(NotFoundException);
  });
});
