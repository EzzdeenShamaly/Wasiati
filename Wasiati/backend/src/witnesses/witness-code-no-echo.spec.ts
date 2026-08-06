import { NotFoundException } from '@nestjs/common';
import { WitnessesService } from './witnesses.service';

/**
 * POST /witnesses/:witnessId/send-code is intentionally UNAUTHENTICATED (the witness
 * may not be a platform user) — the OTP delivered over SMS is the possession factor.
 * The leak was that the response echoed that live, consumable signing code (via
 * devEchoCode when OTP_DEV_ECHO=true), so any anonymous caller who knew a witness id
 * got a code good for confirmSignature. The code must only ever go out over SMS.
 */
describe('WitnessesService.sendSigningCode — no live-OTP echo on the public endpoint', () => {
  it('never returns the OTP in the response, even when OTP echo is active', async () => {
    const prisma: any = {
      witness: { findUnique: async () => ({ id: 'w1', phone: '+100', fullName: 'A' }) },
    };
    // devEchoCode would hand back the live code if the service still called it.
    const otp: any = {
      issue: jest.fn().mockResolvedValue('424794'),
      devEchoCode: jest.fn((c: string) => c),
    };
    const svc = new WitnessesService(prisma, {} as any, otp, {} as any, { get: jest.fn() } as any, { incrWithTtl: async () => 1 } as any);

    const res = await svc.sendSigningCode('w1');

    expect(res).toEqual({ sent: true });
    expect(res).not.toHaveProperty('devCode');
    expect(otp.issue).toHaveBeenCalledWith('+100', 'witness_sign'); // still sent over SMS
    expect(otp.devEchoCode).not.toHaveBeenCalled(); // never echoed back
  });

  it('404s an unknown witness id', async () => {
    const prisma: any = { witness: { findUnique: async () => null } };
    const svc = new WitnessesService(prisma, {} as any, { issue: jest.fn() } as any, {} as any, { get: jest.fn() } as any, { incrWithTtl: async () => 1 } as any);
    await expect(svc.sendSigningCode('nope')).rejects.toBeInstanceOf(NotFoundException);
  });
});
