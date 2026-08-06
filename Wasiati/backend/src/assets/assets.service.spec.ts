import { NotFoundException } from '@nestjs/common';
import { AssetsService, assetsToCsv } from './assets.service';

describe('AssetsService.update ownership', () => {
  const OWNER = 'user-owner';

  function svc(asset: any) {
    const update = jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'a1', ...data }));
    const prisma = {
      asset: { findUnique: jest.fn().mockResolvedValue(asset), update },
    } as any;
    return { service: new AssetsService(prisma), update };
  }

  it('updates the caller’s own asset', async () => {
    const { service, update } = svc({ id: 'a1', will: { ownerId: OWNER } });
    await expect(service.update('a1', OWNER, { label: 'Renamed' })).resolves.toMatchObject({ label: 'Renamed' });
    expect(update).toHaveBeenCalledTimes(1);
  });

  it('hides another user’s asset behind NotFound (no update executed)', async () => {
    const { service, update } = svc({ id: 'a1', will: { ownerId: OWNER } });
    await expect(service.update('a1', 'intruder', { label: 'X' })).rejects.toBeInstanceOf(NotFoundException);
    expect(update).not.toHaveBeenCalled();
  });

  it('NotFound when the asset does not exist', async () => {
    const { service } = svc(null);
    await expect(service.update('missing', OWNER, {})).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('assetsToCsv', () => {
  it('quotes cells, doubles embedded quotes, and separates rows with CRLF', () => {
    const csv = assetsToCsv([
      { type: 'BANK_ACCOUNT', label: 'Say "salam"', institution: 'Al, Rajhi', estimatedValue: 1000, currency: 'SAR' },
    ]);
    expect(csv).toContain('"Say ""salam"""');
    expect(csv).toContain('"Al, Rajhi"');
    expect(csv.endsWith('\r\n')).toBe(true);
  });

  it('neutralises formula injection in hostile labels', () => {
    const csv = assetsToCsv([{ type: 'OTHER', label: '=HYPERLINK("http://evil")' }]);
    // The cell must not begin with a live "=" once unquoted.
    expect(csv).toContain(`"'=HYPERLINK`);
  });

  it('labels liabilities as loans and leaves valueless cells empty', () => {
    const csv = assetsToCsv([{ type: 'LIABILITY', label: 'Car loan' }]);
    expect(csv).toContain('"Loan / liability"');
    const dataLine = csv.trim().split('\r\n')[1];
    expect(dataLine).toContain('""'); // empty value cell, still quoted
  });
});
