import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { FilesService } from './files.service';
import { FilesController } from './files.controller';

/**
 * The owner-facing download route. Two guarantees live here:
 *   1. OWNERSHIP — a download is keyed by row id, and the row's userId must match
 *      the JWT subject. Guessing another user's id must not hand out their bytes.
 *   2. FAIL CLOSED — the malware gate refuses PENDING, INFECTED *and* an object with
 *      no FileObject row at all (the row-less case used to skip the gate entirely).
 */
const VIDEO = {
  id: 'f1',
  userId: 'user-1',
  kind: 'video_legacy',
  key: 'legacy-videos/user-1/a.mp4',
  contentType: 'video/mp4',
  sizeBytes: 40,
  scanStatus: 'CLEAN',
};
const DOC = {
  id: 'f2',
  userId: 'user-1',
  kind: 'id_document',
  key: 'id-documents/user-1/b.pdf',
  contentType: 'application/pdf',
  sizeBytes: 10,
  scanStatus: 'CLEAN',
};

function makeService(rows: any[] = []) {
  const storage: any = {
    name: 'S3',
    configured: true,
    presignDownload: jest.fn(async (key: string) => `https://s3/get/${key}`),
    deleteObject: jest.fn(),
  };
  const prisma: any = {
    fileObject: {
      // The service looks rows up by id (ownership) and by key (the scan gate).
      findUnique: jest.fn(
        async ({ where }: any) =>
          rows.find((r) => (where.id !== undefined ? r.id === where.id : r.key === where.key)) ?? null,
      ),
    },
  };
  const config = { get: () => undefined } as any;
  return { svc: new FilesService(storage, prisma, config, { hasFeature: async () => true } as any), storage };
}

describe('FilesService.presignDownloadOwned — ownership', () => {
  it('returns a URL for a CLEAN file the caller owns', async () => {
    const { svc, storage } = makeService([VIDEO]);
    await expect(svc.presignDownloadOwned('user-1', 'f1')).resolves.toEqual({
      url: 'https://s3/get/legacy-videos/user-1/a.mp4',
    });
    expect(storage.presignDownload).toHaveBeenCalled();
  });

  it('REFUSES another user’s file id (IDOR) — and never touches storage', async () => {
    const { svc, storage } = makeService([VIDEO]);
    await expect(svc.presignDownloadOwned('user-2', 'f1')).rejects.toThrow(BadRequestException);
    expect(storage.presignDownload).not.toHaveBeenCalled();
  });

  it('gives a stranger’s id and a nonexistent id the SAME answer (no existence oracle)', async () => {
    const { svc } = makeService([VIDEO]);
    const stranger = await svc.presignDownloadOwned('user-2', 'f1').catch((e) => e.message);
    const missing = await svc.presignDownloadOwned('user-2', 'no-such-id').catch((e) => e.message);
    expect(stranger).toBe('File not found.');
    expect(missing).toBe(stranger);
  });

  it('resolves the key from the ROW, pinning disposition per kind', async () => {
    const video = makeService([VIDEO]);
    await video.svc.presignDownloadOwned('user-1', 'f1');
    expect(video.storage.presignDownload).toHaveBeenCalledWith(
      VIDEO.key,
      expect.objectContaining({ contentType: 'video/mp4', disposition: 'inline' }),
    );

    // Anything that isn't a legacy video is forced to download, never rendered.
    const doc = makeService([DOC]);
    await doc.svc.presignDownloadOwned('user-1', 'f2');
    expect(doc.storage.presignDownload).toHaveBeenCalledWith(
      DOC.key,
      expect.objectContaining({ contentType: 'application/octet-stream', disposition: 'attachment' }),
    );
  });
});

describe('FilesService.presignDownloadOwned — malware gate', () => {
  it('REFUSES an INFECTED file the caller owns', async () => {
    const { svc, storage } = makeService([{ ...VIDEO, scanStatus: 'INFECTED' }]);
    await expect(svc.presignDownloadOwned('user-1', 'f1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(storage.presignDownload).not.toHaveBeenCalled();
  });

  it('REFUSES a PENDING (still-scanning) file the caller owns', async () => {
    const { svc, storage } = makeService([{ ...VIDEO, scanStatus: 'PENDING' }]);
    await expect(svc.presignDownloadOwned('user-1', 'f1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(storage.presignDownload).not.toHaveBeenCalled();
  });
});

describe('FilesService.presignDownload — fail-closed regression', () => {
  // The gate used to read `if (file && file.scanStatus !== 'CLEAN')`. With no row
  // for the key the whole malware check was skipped and the URL was handed out.
  it('REFUSES a key with no FileObject row instead of serving it unscanned', async () => {
    const { svc, storage } = makeService([]); // nothing recorded
    await expect(svc.presignDownload('legacy-videos/user-1/ghost.mp4')).rejects.toBeInstanceOf(ForbiddenException);
    expect(storage.presignDownload).not.toHaveBeenCalled();
  });

  it('still serves a key that DOES have a CLEAN row', async () => {
    const { svc } = makeService([VIDEO]);
    await expect(svc.presignDownload(VIDEO.key)).resolves.toBe('https://s3/get/legacy-videos/user-1/a.mp4');
  });
});

describe('FilesController GET :id/download', () => {
  it('scopes the download to the JWT subject, not to anything the client sends', async () => {
    const files: any = { presignDownloadOwned: jest.fn().mockResolvedValue({ url: 'https://s3/get/x' }) };
    const ctl = new FilesController(files);
    await expect(ctl.download({ userId: 'user-1' }, 'f1')).resolves.toEqual({ url: 'https://s3/get/x' });
    expect(files.presignDownloadOwned).toHaveBeenCalledWith('user-1', 'f1');
  });
});
