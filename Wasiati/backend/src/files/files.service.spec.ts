import { BadRequestException } from '@nestjs/common';
import { FilesService, USER_STORAGE_QUOTA_BYTES } from './files.service';

/**
 * Uploads go direct-to-storage via a presigned PUT, so the security guarantees live
 * HERE: allowed content-types only, keys namespaced to the owner, and a hard 1 GB
 * per-user quota enforced at presign AND re-checked at confirm.
 */
const MB = 1024 * 1024;

function makeService(opts: { usedBytes?: number; files?: any[]; scheduledPurgeAt?: Date } = {}) {
  const rows: any[] = opts.files ?? [];
  const calls: any[] = [];
  const storage: any = {
    name: 'S3',
    configured: true,
    presignUpload: async (p: any) => {
      calls.push(p);
      return { uploadUrl: 'https://s3/put', key: p.key, requiredHeaders: {}, expiresInSeconds: 300 };
    },
    presignDownload: async (key: string) => `https://s3/get/${key}`,
  };
  const prisma: any = {
    fileObject: {
      aggregate: async ({ where }: any) => ({
        _sum: {
          sizeBytes:
            opts.usedBytes ??
            rows.filter((r) => r.userId === where.userId).reduce((s, r) => s + r.sizeBytes, 0),
        },
      }),
      create: async ({ data }: any) => {
        const row = { id: `f${rows.length + 1}`, ...data };
        rows.push(row);
        return row;
      },
      findUnique: async ({ where }: any) => rows.find((r) => r.id === where.id) ?? null,
      findMany: async ({ where }: any) => rows.filter((r) => r.userId === where.userId),
      delete: async ({ where }: any) => {
        const i = rows.findIndex((r) => r.id === where.id);
        return rows.splice(i, 1)[0];
      },
    },
    // A live account by default: uploads are refused once scheduledPurgeAt is set
    // (see the purge-gate suite below).
    user: { findUnique: async () => ({ scheduledPurgeAt: opts.scheduledPurgeAt ?? null }) },
    // confirmUpload runs its quota-check + insert inside a transaction.
    $transaction: async (fn: any) => fn(prisma),
  };
  // ConfigService double: malware scan off by default in these existing tests.
  const config = { get: () => undefined } as any;
  return { svc: new FilesService(storage, prisma, config, { hasFeature: async () => true } as any), calls, rows };
}

describe('FilesService.presignUpload', () => {
  it('issues a presigned upload for an allowed type, keyed under the owner', async () => {
    const { svc } = makeService();
    const res = await svc.presignUpload('user-1', 'id_document', 'application/pdf', 2 * MB);
    expect(res.key).toMatch(/^id-documents\/user-1\/[0-9a-f-]+\.pdf$/);
    expect(res.kind).toBe('id_document');
  });

  it('accepts video types for video_legacy', async () => {
    const { svc } = makeService();
    for (const ct of ['video/mp4', 'video/webm', 'video/quicktime']) {
      const res = await svc.presignUpload('user-1', 'video_legacy', ct, 10 * MB);
      expect(res.key.startsWith('legacy-videos/user-1/')).toBe(true);
    }
  });

  it('REJECTS a disallowed content-type (no executables/svg/html)', async () => {
    const { svc } = makeService();
    for (const bad of ['application/x-msdownload', 'image/svg+xml', 'text/html']) {
      await expect(svc.presignUpload('user-1', 'video_legacy', bad, MB)).rejects.toThrow(BadRequestException);
    }
  });

  it('REJECTS a file over the per-file cap', async () => {
    const { svc } = makeService();
    await expect(svc.presignUpload('user-1', 'id_document', 'application/pdf', 20 * MB)).rejects.toThrow(/too large/i);
  });

  it('REJECTS an upload that would exceed the 1 GB user quota', async () => {
    // Already using 900 MB; a 200 MB upload overflows.
    const { svc } = makeService({ usedBytes: 900 * MB });
    await expect(svc.presignUpload('user-1', 'video_legacy', 'video/mp4', 200 * MB)).rejects.toThrow(/1 GB storage/i);
  });

  it('allows an upload that fits within the remaining quota', async () => {
    const { svc } = makeService({ usedBytes: 800 * MB });
    await expect(svc.presignUpload('user-1', 'video_legacy', 'video/mp4', 100 * MB)).resolves.toBeDefined();
  });
});

describe('FilesService.confirmUpload — quota re-check', () => {
  it('records the file and re-checks the quota against the REAL size', async () => {
    const { svc, rows } = makeService();
    const key = 'legacy-videos/user-1/abc.mp4';
    await svc.confirmUpload('user-1', 'video_legacy', key, 'video/mp4', 50 * MB);
    expect(rows).toHaveLength(1);
    expect(rows[0].sizeBytes).toBe(50 * MB);
  });

  it('REJECTS at confirm if the real size overflows the quota (client lied at presign)', async () => {
    const { svc } = makeService({ usedBytes: USER_STORAGE_QUOTA_BYTES - 10 * MB });
    const key = 'legacy-videos/user-1/big.mp4';
    await expect(svc.confirmUpload('user-1', 'video_legacy', key, 'video/mp4', 50 * MB)).rejects.toThrow(/1 GB storage/i);
  });

  it('REJECTS confirming another user’s key (upload-side IDOR)', async () => {
    const { svc } = makeService();
    await expect(
      svc.confirmUpload('user-1', 'video_legacy', 'legacy-videos/user-2/x.mp4', 'video/mp4', MB),
    ).rejects.toThrow(BadRequestException);
  });

  it('re-sums the quota INSIDE the transaction (closes the concurrent-confirm race)', async () => {
    // At 990 MB used, a 50 MB confirm must be rejected — even though presign's
    // provisional check might have passed against a staler total.
    const { svc } = makeService({ usedBytes: 990 * MB });
    await expect(
      svc.confirmUpload('user-1', 'video_legacy', 'legacy-videos/user-1/a.mp4', 'video/mp4', 50 * MB),
    ).rejects.toThrow(/1 GB storage/i);
  });
});

describe('an account awaiting posthumous purge accepts no new bytes', () => {
  // Closes the race the retention purge cannot otherwise win: a presigned PUT stays
  // spendable for its whole TTL, so an upload started before the erasure sweep could
  // land AFTER the sweep verified the prefix empty — files surviving behind a tombstone
  // that says they were destroyed.
  const scheduled = { scheduledPurgeAt: new Date('2026-10-01T00:00:00Z') };

  it('refuses to presign, so no URL that could land bytes is ever minted', async () => {
    const { svc, calls } = makeService(scheduled);
    await expect(svc.presignUpload('user-1', 'id_document', 'application/pdf', MB)).rejects.toThrow(
      /no longer accept uploads/i,
    );
    expect(calls).toHaveLength(0);
  });

  it('refuses to confirm too — a URL issued before the account closed is not a way in', async () => {
    const { svc, rows } = makeService(scheduled);
    await expect(
      svc.confirmUpload('user-1', 'id_document', 'id-documents/user-1/a.pdf', 'application/pdf', MB),
    ).rejects.toThrow(/no longer accept uploads/i);
    expect(rows).toHaveLength(0);
  });
});

describe('FilesService quota + delete', () => {
  it('reports used / remaining against the 1 GB quota', async () => {
    const { svc } = makeService({ usedBytes: 300 * MB });
    const q = await svc.quota('user-1');
    expect(q.quotaBytes).toBe(USER_STORAGE_QUOTA_BYTES);
    expect(q.usedBytes).toBe(300 * MB);
    expect(q.remainingBytes).toBe(USER_STORAGE_QUOTA_BYTES - 300 * MB);
  });

  it('deleting a file frees the quota; a stranger cannot delete it', async () => {
    const { svc, rows } = makeService();
    await svc.confirmUpload('user-1', 'video_legacy', 'legacy-videos/user-1/a.mp4', 'video/mp4', 40 * MB);
    const id = rows[0].id;
    await expect(svc.deleteOwned('user-2', id)).rejects.toThrow(BadRequestException); // not yours
    await expect(svc.deleteOwned('user-1', id)).resolves.toEqual({ deleted: true });
    expect(await svc.usedBytes('user-1')).toBe(0);
  });

  describe('assertOwnedKey', () => {
    it('accepts the owner’s key, rejects others and traversal', () => {
      const { svc } = makeService();
      expect(() => svc.assertOwnedKey('u1', 'id-documents/u1/a.pdf')).not.toThrow();
      expect(() => svc.assertOwnedKey('u1', 'id-documents/u2/a.pdf')).toThrow();
      expect(() => svc.assertOwnedKey('u1', 'secrets/u1/a.pdf')).toThrow();
      expect(() => svc.assertOwnedKey('u1', '../etc/passwd')).toThrow();
    });
  });
});
