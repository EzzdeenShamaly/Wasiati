import { BadRequestException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { OTP_MAX_ATTEMPTS, OtpService } from './otp.service';

/**
 * A 6-digit OTP is only ~10^6 codes. Without a per-code attempt cap, an attacker who
 * rotates IPs past the per-IP throttle can exhaust the space inside the 10-minute
 * TTL and forge a witness signature / death claim / MFA. These tests pin the cap.
 */
function makeDb(codeHash: string) {
  const record = {
    id: 'otp1',
    destination: '+100',
    purpose: 'witness_sign',
    codeHash,
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    consumedAt: null as Date | null,
    attempts: 0,
  };
  const prisma: any = {
    otpCode: {
      findFirst: async () => (record.consumedAt ? null : record),
      updateMany: async ({ where, data }: any) => {
        if (where.id === record.id && record.consumedAt === null) {
          Object.assign(record, data);
          return { count: 1 };
        }
        return { count: 0 };
      },
      update: async ({ data }: any) => {
        Object.assign(record, data);
        return record;
      },
    },
  };
  return { prisma, record };
}

const svc = (prisma: any) => new OtpService(prisma, {} as any, {} as any);

describe('OtpService.verify — brute-force cap', () => {
  it('burns the code after OTP_MAX_ATTEMPTS wrong guesses', async () => {
    const hash = await bcrypt.hash('123456', 10);
    const db = makeDb(hash);
    const s = svc(db.prisma);

    // Wrong guesses up to the limit each return false...
    for (let i = 0; i < OTP_MAX_ATTEMPTS - 1; i++) {
      expect(await s.verify('+100', 'witness_sign', '000000')).toBe(false);
    }
    expect(db.record.consumedAt).toBeNull();

    // ...the last allowed wrong guess burns the code.
    expect(await s.verify('+100', 'witness_sign', '000000')).toBe(false);
    expect(db.record.attempts).toBe(OTP_MAX_ATTEMPTS);
    expect(db.record.consumedAt).not.toBeNull();
  });

  it('rejects any further guess once the code is burned — even the CORRECT one', async () => {
    const hash = await bcrypt.hash('123456', 10);
    const db = makeDb(hash);
    const s = svc(db.prisma);

    for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
      await s.verify('+100', 'witness_sign', '000000');
    }
    // The real code can no longer be used: the burned code is treated as absent.
    await expect(s.verify('+100', 'witness_sign', '123456')).rejects.toThrow(BadRequestException);
  });

  it('a correct guess before the cap still succeeds and consumes the code', async () => {
    const hash = await bcrypt.hash('123456', 10);
    const db = makeDb(hash);
    const s = svc(db.prisma);

    expect(await s.verify('+100', 'witness_sign', '999999')).toBe(false); // one miss
    expect(await s.verify('+100', 'witness_sign', '123456')).toBe(true); // then hit
    expect(db.record.consumedAt).not.toBeNull();
  });

  it('the cap is small enough that the 10^6 space cannot be exhausted in the TTL', () => {
    // Sanity: with <=5 guesses per code, a single code exposes 5/10^6 = 0.0005%.
    expect(OTP_MAX_ATTEMPTS).toBeLessThanOrEqual(5);
  });
});

describe('OtpService.issue — channel routing', () => {
  // The channel decides transport AND what `destination` means. The 'email' channel is
  // what lets a phoneless owner complete will step-up (DECISIONS §17). `verify` keys off
  // the SAME (destination, purpose) pair, so what `issue` persists here is what verify reads.
  function makeIssueSvc() {
    const created: any[] = [];
    const prisma: any = {
      otpCode: { create: async ({ data }: any) => { created.push(data); return { id: 'o1', ...data }; } },
    };
    const notifications: any = {
      // sendSms/sendEmail return whether the code was actually dispatched (true). issue()
      // now honours that boolean and throws when it is false, so these mocks report success.
      sendSms: jest.fn().mockResolvedValue(true),
      sendWhatsapp: jest.fn().mockResolvedValue(undefined),
      sendEmail: jest.fn().mockResolvedValue(true),
    };
    const config: any = { get: () => undefined }; // OTP_DEV_ECHO off — production shape
    return { svc: new OtpService(prisma, notifications, config), notifications, created };
  }

  it('sms (default) delivers by SMS, never by email', async () => {
    const { svc, notifications } = makeIssueSvc();
    await svc.issue('+15551230000', 'will_step_up', 'u1');
    expect(notifications.sendSms).toHaveBeenCalledTimes(1);
    expect(notifications.sendSms.mock.calls[0][0]).toBe('+15551230000');
    expect(notifications.sendEmail).not.toHaveBeenCalled();
  });

  it('email channel delivers to the email address, never by SMS', async () => {
    const { svc, notifications } = makeIssueSvc();
    await svc.issue('owner@x.com', 'will_step_up', 'u1', 'email');
    expect(notifications.sendEmail).toHaveBeenCalledTimes(1);
    expect(notifications.sendEmail.mock.calls[0][0]).toBe('owner@x.com'); // to
    expect(notifications.sendSms).not.toHaveBeenCalled();
  });

  it('persists the hash keyed by (destination, purpose) so verify matches the same channel', async () => {
    const { svc, created } = makeIssueSvc();
    await svc.issue('owner@x.com', 'will_step_up', 'u1', 'email');
    expect(created[0].destination).toBe('owner@x.com');
    expect(created[0].purpose).toBe('will_step_up');
    expect(created[0].codeHash).not.toBe(created[0].destination); // stored hashed, not plaintext
  });
});
