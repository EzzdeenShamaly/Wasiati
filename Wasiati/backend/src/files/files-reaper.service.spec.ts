import { FilesReaperService } from './files-reaper.service';

/**
 * The reaper must delete ONLY orphans: objects with no FileObject row that are older
 * than the grace window. It must never touch a confirmed file, nor a fresh
 * (still-uploading) unconfirmed one.
 */
const HOUR = 60 * 60 * 1000;

function makeReaper(opts: {
  objects: { key: string; ageHours: number }[];
  confirmedKeys?: string[];
  configured?: boolean;
  graceHours?: number;
}) {
  const now = new Date('2026-07-11T12:00:00Z');
  const deleted: string[] = [];
  const storage: any = {
    configured: opts.configured ?? true,
    listObjects: async (prefix: string) =>
      opts.objects
        .filter((o) => o.key.startsWith(prefix))
        .map((o) => ({ key: o.key, lastModified: new Date(now.getTime() - o.ageHours * HOUR), sizeBytes: 1 })),
    deleteObject: async (key: string) => {
      deleted.push(key);
    },
  };
  const prisma: any = {
    fileObject: { findMany: async () => (opts.confirmedKeys ?? []).map((key) => ({ key })) },
  };
  const config: any = { get: () => opts.graceHours };
  return { svc: new FilesReaperService(prisma, config, storage), deleted, now };
}

describe('FilesReaperService.reap', () => {
  it('deletes an unconfirmed object older than the grace window', async () => {
    const { svc, deleted, now } = makeReaper({
      objects: [{ key: 'legacy-videos/u1/orphan.mp4', ageHours: 48 }],
      graceHours: 24,
    });
    const res = await svc.reap(now);
    expect(res.deleted).toBe(1);
    expect(deleted).toEqual(['legacy-videos/u1/orphan.mp4']);
  });

  it('NEVER deletes a confirmed object, however old', async () => {
    const { svc, deleted, now } = makeReaper({
      objects: [{ key: 'legacy-videos/u1/real.mp4', ageHours: 1000 }],
      confirmedKeys: ['legacy-videos/u1/real.mp4'],
      graceHours: 24,
    });
    const res = await svc.reap(now);
    expect(res.deleted).toBe(0);
    expect(deleted).toEqual([]);
  });

  it('NEVER deletes a fresh unconfirmed object still inside the grace window', async () => {
    const { svc, deleted, now } = makeReaper({
      objects: [{ key: 'id-documents/u1/inflight.pdf', ageHours: 2 }], // uploaded 2h ago
      graceHours: 24,
    });
    await svc.reap(now);
    expect(deleted).toEqual([]);
  });

  it('scans every upload prefix', async () => {
    const { svc, deleted, now } = makeReaper({
      objects: [
        { key: 'legacy-videos/u1/a.mp4', ageHours: 48 },
        { key: 'id-documents/u2/b.pdf', ageHours: 48 },
        { key: 'death-certificates/u3/c.pdf', ageHours: 48 },
      ],
      graceHours: 24,
    });
    const res = await svc.reap(now);
    expect(res.scanned).toBe(3);
    expect(deleted.sort()).toEqual([
      'death-certificates/u3/c.pdf',
      'id-documents/u2/b.pdf',
      'legacy-videos/u1/a.mp4',
    ]);
  });

  it('is a no-op when storage is not configured', async () => {
    const { svc, deleted, now } = makeReaper({
      objects: [{ key: 'legacy-videos/u1/x.mp4', ageHours: 999 }],
      configured: false,
    });
    const res = await svc.reap(now);
    expect(res).toEqual({ scanned: 0, deleted: 0 });
    expect(deleted).toEqual([]);
  });

  it('defaults the grace window to 24h when unconfigured', async () => {
    // ageHours 25 > default 24 → reaped; ageHours 23 < 24 → kept.
    const r1 = makeReaper({ objects: [{ key: 'legacy-videos/u1/old.mp4', ageHours: 25 }], graceHours: undefined });
    const r2 = makeReaper({ objects: [{ key: 'legacy-videos/u1/new.mp4', ageHours: 23 }], graceHours: undefined });
    expect((await r1.svc.reap(r1.now)).deleted).toBe(1);
    expect((await r2.svc.reap(r2.now)).deleted).toBe(0);
  });
});
