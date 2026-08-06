import { ForbiddenException, Logger, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { createHmac } from 'crypto';
import { FilesService } from './files.service';
import { FilesScanController } from './files-scan.controller';

/**
 * The malware-scan quarantine gate: a file is not served until a scanner clears it,
 * and the verdict webhook only trusts an HMAC-signed call.
 */
describe('Files malware-scan gate', () => {
  const KEY = 'legacy-videos/user-1/abc.mp4';

  function svc(fileRow: any, scanEnabled = false) {
    const storage = {
      configured: true,
      presignDownload: jest.fn().mockResolvedValue('https://s3/get'),
      deleteObject: jest.fn().mockResolvedValue(undefined),
      deleteAllVersions: jest.fn().mockResolvedValue({
        method: 'versions',
        objectsDeleted: 1,
        versionsDeleted: 1,
        deleteMarkersDeleted: 0,
        verifiedEmpty: true,
      }),
    } as any;
    const prisma = {
      fileObject: {
        findUnique: jest.fn().mockResolvedValue(fileRow),
        update: jest.fn().mockResolvedValue({}),
      },
    } as any;
    const config = { get: (k: string) => (k === 'MALWARE_SCAN_ENABLED' ? (scanEnabled ? 'true' : 'false') : undefined) } as any;
    return { service: new FilesService(storage, prisma, config, { hasFeature: async () => true } as any), storage, prisma };
  }

  describe('presignDownload gate', () => {
    it('serves a CLEAN file', async () => {
      const { service, storage } = svc({ key: KEY, kind: 'video_legacy', contentType: 'video/mp4', scanStatus: 'CLEAN' });
      await expect(service.presignDownload(KEY)).resolves.toBe('https://s3/get');
      expect(storage.presignDownload).toHaveBeenCalled();
    });

    it('refuses a PENDING (still-scanning) file', async () => {
      const { service, storage } = svc({ key: KEY, kind: 'video_legacy', scanStatus: 'PENDING' });
      await expect(service.presignDownload(KEY)).rejects.toBeInstanceOf(ForbiddenException);
      expect(storage.presignDownload).not.toHaveBeenCalled();
    });

    it('refuses an INFECTED file', async () => {
      const { service, storage } = svc({ key: KEY, kind: 'video_legacy', scanStatus: 'INFECTED' });
      await expect(service.presignDownload(KEY)).rejects.toBeInstanceOf(ForbiddenException);
      expect(storage.presignDownload).not.toHaveBeenCalled();
    });
  });

  describe('applyScanResult', () => {
    it('CLEAN keeps the object; INFECTED updates status AND erases EVERY version', async () => {
      const clean = svc({ key: KEY, scanStatus: 'PENDING' });
      await expect(clean.service.applyScanResult(KEY, true)).resolves.toEqual({ scanStatus: 'CLEAN' });
      expect(clean.storage.deleteAllVersions).not.toHaveBeenCalled();

      // deleteAllVersions, NOT deleteObject: on a versioned bucket a plain delete only
      // writes a delete marker, leaving the malware fetchable by version id forever.
      const infected = svc({ key: KEY, scanStatus: 'PENDING' });
      await expect(infected.service.applyScanResult(KEY, false)).resolves.toEqual({ scanStatus: 'INFECTED' });
      expect(infected.storage.deleteAllVersions).toHaveBeenCalledWith(KEY);
      expect(infected.storage.deleteObject).not.toHaveBeenCalled();
    });

    it('a failed erase is logged, not swallowed, and never blocks the INFECTED verdict', async () => {
      // It used to be `.catch(() => undefined)`: infected bytes could stay in storage
      // silently and forever. The verdict must still be recorded so the file stays blocked.
      const infected = svc({ key: KEY, scanStatus: 'PENDING' });
      infected.storage.deleteAllVersions.mockRejectedValueOnce(new Error('access denied'));
      const logged = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);

      await expect(infected.service.applyScanResult(KEY, false)).resolves.toEqual({ scanStatus: 'INFECTED' });
      expect(logged).toHaveBeenCalledWith(expect.stringContaining(KEY));
      logged.mockRestore();
    });

    it('throws NotFound for an unknown key', async () => {
      const { service } = svc(null);
      await expect(service.applyScanResult('missing', true)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('scan-callback webhook auth', () => {
    const SECRET = 'scan-secret';
    function controller() {
      const files = { applyScanResult: jest.fn().mockResolvedValue({ scanStatus: 'CLEAN' }) } as any;
      const config = { get: (k: string) => (k === 'FILES_SCAN_WEBHOOK_SECRET' ? SECRET : undefined) } as any;
      return { ctl: new FilesScanController(files, config), files };
    }
    const sign = (body: any) => createHmac('sha256', SECRET).update(JSON.stringify(body)).digest('hex');

    it('accepts a correctly-signed verdict and applies it', async () => {
      const { ctl, files } = controller();
      const body = { key: KEY, status: 'CLEAN' as const };
      await expect(ctl.scanCallback(body, sign(body))).resolves.toEqual({ scanStatus: 'CLEAN' });
      expect(files.applyScanResult).toHaveBeenCalledWith(KEY, true);
    });

    it('rejects a forged/absent signature', async () => {
      const { ctl, files } = controller();
      const body = { key: KEY, status: 'INFECTED' as const };
      await expect(ctl.scanCallback(body, 'deadbeef')).rejects.toBeInstanceOf(UnauthorizedException);
      await expect(ctl.scanCallback(body, undefined)).rejects.toBeInstanceOf(UnauthorizedException);
      expect(files.applyScanResult).not.toHaveBeenCalled();
    });

    it('fails closed when no webhook secret is configured', async () => {
      const files = { applyScanResult: jest.fn() } as any;
      const config = { get: () => undefined } as any;
      const ctl = new FilesScanController(files, config);
      await expect(ctl.scanCallback({ key: KEY, status: 'CLEAN' }, 'anything')).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
