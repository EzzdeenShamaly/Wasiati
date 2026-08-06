import { ForbiddenException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Region, VerificationStatus } from '@prisma/client';
import { NafathService } from './nafath.service';

describe('NafathService', () => {
  const config = {
    get: (k: string) =>
      ({ NAFATH_BASE_URL: 'https://nafath.example', NAFATH_API_KEY: 'k' })[k],
  } as unknown as ConfigService;

  const prismaFor = (region: Region | null) =>
    ({
      user: { findUnique: jest.fn().mockResolvedValue(region ? { region } : null) },
      nafathVerification: { create: jest.fn() },
    }) as any;

  const fetchSpy = jest.spyOn(global, 'fetch');
  afterEach(() => fetchSpy.mockReset());

  it('refuses a non-Saudi user — Nafath only identifies Saudi residents', async () => {
    const prisma = prismaFor(Region.CA);
    const svc = new NafathService(config, prisma);

    await expect(svc.initiate('u1', '1234567890')).rejects.toThrow(ForbiddenException);
    // The region check must happen BEFORE we call the government API.
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('refuses US and Canadian users too', async () => {
    for (const region of [Region.US, Region.CA]) {
      const svc = new NafathService(config, prismaFor(region));
      await expect(svc.initiate('u1', '1234567890')).rejects.toThrow(
        /only available to users in Saudi Arabia/,
      );
    }
  });

  it('lets a KSA user through to Nafath', async () => {
    const prisma = prismaFor(Region.KSA);
    prisma.user.update = jest.fn();
    const svc = new NafathService(config, prisma);
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({ transId: 't1', random: '42' }),
    } as Response);

    await expect(svc.initiate('u1', '1234567890')).resolves.toMatchObject({
      transId: 't1',
      random: '42',
    });
    expect(fetchSpy).toHaveBeenCalled();
  });

  it('stays unconfigured-safe: no credentials means 503, not a region leak', async () => {
    const bare = { get: () => undefined } as unknown as ConfigService;
    const svc = new NafathService(bare, prismaFor(Region.KSA));
    await expect(svc.initiate('u1', '1234567890')).rejects.toThrow(ServiceUnavailableException);
  });

  describe('handleCallback is fail-closed', () => {
    const secretless = {
      get: (k: string) => ({ NAFATH_BASE_URL: 'https://nafath.example', NAFATH_API_KEY: 'k' })[k],
    } as unknown as ConfigService;
    const withSecret = {
      get: (k: string) =>
        ({ NAFATH_BASE_URL: 'https://nafath.example', NAFATH_API_KEY: 'k', NAFATH_CALLBACK_SECRET: 'right' })[k],
    } as unknown as ConfigService;
    const cbPrisma = (record: any = null) =>
      ({
        nafathVerification: { findUnique: jest.fn().mockResolvedValue(record), update: jest.fn() },
        user: { update: jest.fn() },
      }) as any;

    it('rejects when NAFATH_CALLBACK_SECRET is unset — the self-verification bypass is closed', async () => {
      // The heart of the fix: previously an unset secret SKIPPED the check, so any Saudi user
      // could POST their own transId + status:COMPLETED and mark themselves VERIFIED.
      const prisma = cbPrisma();
      const svc = new NafathService(secretless, prisma);
      await expect(svc.handleCallback({ transId: 't1', status: 'COMPLETED' })).rejects.toThrow(
        ServiceUnavailableException,
      );
      expect(prisma.nafathVerification.findUnique).not.toHaveBeenCalled();
      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('rejects a wrong or missing secret and persists nothing', async () => {
      const prisma = cbPrisma({ transId: 't1', userId: 'u1' });
      const svc = new NafathService(withSecret, prisma);
      await expect(svc.handleCallback({ transId: 't1', status: 'COMPLETED', secret: 'wrong' })).rejects.toThrow(
        /Invalid callback signature/,
      );
      await expect(svc.handleCallback({ transId: 't1', status: 'COMPLETED' })).rejects.toThrow(
        /Invalid callback signature/,
      );
      expect(prisma.user.update).not.toHaveBeenCalled();
    });

    it('accepts the correct secret and persists the mapped status', async () => {
      const prisma = cbPrisma({ transId: 't1', userId: 'u1' });
      const svc = new NafathService(withSecret, prisma);
      await expect(svc.handleCallback({ transId: 't1', status: 'COMPLETED', secret: 'right' })).resolves.toEqual({
        ok: true,
      });
      expect(prisma.user.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: expect.objectContaining({ idVerificationStatus: VerificationStatus.VERIFIED }) }),
      );
    });
  });
});
