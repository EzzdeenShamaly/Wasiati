import { DataRetentionService } from './data-retention.service';
import { UPLOAD_PREFIXES } from '../files/files.service';

/**
 * The posthumous purge tells a bereaved family, and a regulator, that the deceased's
 * records were PERMANENTLY erased. These tests pin the two things that make that claim
 * true rather than merely asserted:
 *
 *   1. the stored objects are erased and VERIFIED before the database transaction, so a
 *      tombstone cannot exist over surviving bytes; and
 *   2. any failure aborts BEFORE the rows are touched, leaving scheduledPurgeAt intact
 *      so tonight's failure is simply retried tomorrow.
 *
 * Previously purgeUser() deleted rows and wrote the tombstone in one transaction and
 * never called storage at all: every id document, death certificate and legacy video
 * stayed in the bucket while the log recorded their destruction.
 */

const erased = (over: Partial<Record<string, unknown>> = {}) => ({
  method: 'versions',
  objectsDeleted: 2,
  versionsDeleted: 3,
  deleteMarkersDeleted: 1,
  verifiedEmpty: true,
  ...over,
});

const redacted = (over: Record<string, unknown> = {}) => ({
  provider: 'Stripe Identity',
  supported: true,
  sessionsFound: 1,
  redactionRequested: 1,
  alreadyRedacted: 0,
  completesWithinDays: 4,
  ...over,
});

/** Records every database operation in order, so we can assert what ran and when. */
function harness(opts: { keys?: string[]; storage?: any; identity?: any; rail?: string } = {}) {
  const ops: string[] = [];
  const swept: string[] = [];
  let tombstone: any;

  const tx: any = new Proxy(
    {},
    {
      get: (_t, model: string) =>
        new Proxy(
          {},
          {
            get: (_m, op: string) => async (args: any) => {
              ops.push(`db:${model}.${op}`);
              if (model === 'dataPurgeLog' && op === 'create') {
                tombstone = args.data;
                return args.data;
              }
              return op === 'deleteMany' || op === 'updateMany' ? { count: 1 } : {};
            },
          },
        ),
    },
  );

  const prisma: any = {
    will: { findMany: async () => [] },
    vault: { findUnique: async () => null },
    fileObject: { findMany: async () => (opts.keys ?? []).map((key) => ({ key })) },
    user: { findUnique: async () => ({ idVerificationProvider: opts.rail ?? null }) },
    $transaction: async (fn: any) => fn(tx),
  };

  const storage: any = opts.storage ?? {
    configured: true,
    purgePrefix: async (prefix: string) => {
      ops.push(`storage:purge ${prefix}`);
      swept.push(prefix);
      return erased();
    },
  };

  const identity: any = opts.identity ?? {
    redactPersonalData: async () => {
      ops.push('identity:redact');
      return redacted();
    },
  };

  const config: any = { get: () => undefined };
  const svc = new DataRetentionService(prisma, config, {} as any, storage, identity);
  return { svc, ops, swept, get tombstone() { return tombstone; } };
}

describe('purgeUser erases stored objects before it deletes anything', () => {
  it('sweeps every upload prefix, scoped to that user, BEFORE the transaction', async () => {
    const h = harness({ keys: ['id-documents/u1/a.pdf'] });
    await h.svc.purgeUser('u1');

    // Scoped to the user's own folder under each kind — never a bare prefix, which
    // would erase every user's documents.
    expect(h.swept).toEqual(UPLOAD_PREFIXES.map((p) => `${p}/u1/`));
    expect(h.swept.length).toBeGreaterThan(0);

    // Ordering is the whole safety argument: all storage work precedes all DB work.
    const firstDbOp = h.ops.findIndex((o) => o.startsWith('db:'));
    const lastStorageOp = h.ops.map((o) => o.startsWith('storage:')).lastIndexOf(true);
    expect(lastStorageOp).toBeLessThan(firstDbOp);
  });

  it('sweeps by PREFIX even when the database records no files (unconfirmed uploads)', async () => {
    // A presigned-and-PUT upload that was never confirmed has no FileObject row and is
    // just as sensitive. Deleting only recorded keys would leave it behind.
    const h = harness({ keys: [] });
    await h.svc.purgeUser('u1');
    expect(h.swept).toEqual(UPLOAD_PREFIXES.map((p) => `${p}/u1/`));
  });

  it('writes the erasure EVIDENCE into the tombstone, and counts the file rows', async () => {
    const h = harness({ keys: ['id-documents/u1/a.pdf', 'legacy-videos/u1/b.mp4'] });
    await h.svc.purgeUser('u1');

    const storage = h.tombstone.recordsDeleted.storage;
    expect(storage.method).toBe('versions');
    expect(storage.objectsDeleted).toBe(2 * UPLOAD_PREFIXES.length);
    expect(storage.versionsDeleted).toBe(3 * UPLOAD_PREFIXES.length);
    expect(storage.recordedKeys).toBe(2);
    expect(storage.verifiedEmptyAt).toEqual(expect.any(String));
    // FileObject rows are cascade-deleted with the user, so they were never counted —
    // the tombstone claimed a purge without accounting for the documents.
    expect(h.ops).toContain('db:fileObject.deleteMany');
    expect(h.tombstone.recordsDeleted.fileObjects).toBe(1);
  });
});

describe('an unverified erasure aborts the purge, changing nothing', () => {
  it('throws and touches NO database row when a prefix will not verify empty', async () => {
    const h = harness({
      keys: ['id-documents/u1/a.pdf'],
      storage: {
        configured: true,
        // The dangerous case: deletion "succeeded" but a re-list still shows versions.
        purgePrefix: async () => erased({ verifiedEmpty: false }),
      },
    });

    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/could not be verified/i);
    // Nothing deleted, and above all NO tombstone: the user row and its scheduledPurgeAt
    // survive, so the nightly job simply retries.
    expect(h.ops.filter((o) => o.startsWith('db:'))).toEqual([]);
    expect(h.tombstone).toBeUndefined();
  });

  it('propagates a storage failure instead of purging anyway', async () => {
    const h = harness({
      storage: {
        configured: true,
        purgePrefix: async () => {
          throw new Error('S3 refused 2 deletion(s); first: k [AccessDenied]');
        },
      },
    });
    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/AccessDenied/);
    expect(h.tombstone).toBeUndefined();
  });

  it('REFUSES to purge when storage is unconfigured but files are on record', async () => {
    // Storage misconfigured out from under real objects: erasure is impossible here, so
    // claiming it would be a lie. Fail, and let a correctly-configured run do it.
    const h = harness({
      keys: ['id-documents/u1/a.pdf'],
      storage: { configured: false, purgePrefix: async () => erased() },
    });
    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/storage is not configured/i);
    expect(h.tombstone).toBeUndefined();
  });

  it('but proceeds when there is no storage AND nothing was ever stored', async () => {
    const h = harness({ keys: [], storage: { configured: false, purgePrefix: async () => erased() } });
    await expect(h.svc.purgeUser('u1')).resolves.toBeDefined();
    expect(h.tombstone.recordsDeleted.storage.method).toBe('none');
  });
});

describe('the KYC vendor is told to destroy the identity documents too', () => {
  // The government-ID scan and the selfie are the most sensitive artefacts the product
  // handles, and they never touch our bucket — Stripe holds them, on its own multi-year
  // schedule. Erasing only our storage would leave the passport photo sitting at the
  // vendor behind a tombstone that says everything was destroyed.
  it('redacts at the vendor BEFORE the transaction, and records the evidence', async () => {
    const h = harness({ rail: 'DOCUMENT' });
    await h.svc.purgeUser('u1');

    const firstDbOp = h.ops.findIndex((o) => o.startsWith('db:'));
    expect(h.ops.indexOf('identity:redact')).toBeLessThan(firstDbOp);

    const identity = h.tombstone.recordsDeleted.identity;
    expect(identity.redactionRequested).toBe(1);
    // Redaction is ASYNCHRONOUS at Stripe (up to four days), so the tombstone records the
    // vendor's bound rather than implying the bytes are already gone.
    expect(identity.completesWithinDays).toBe(4);
  });

  it('REFUSES to purge when the user verified on the document rail but the vendor cannot redact', async () => {
    // Sumsub has no redaction implementation, and an unconfigured adapter cannot reach
    // the vendor at all. Either way the documents would outlive the purge, so the
    // tombstone must not be written.
    const h = harness({
      rail: 'DOCUMENT',
      identity: { redactPersonalData: async () => redacted({ supported: false, provider: 'Sumsub' }) },
    });
    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/cannot redact/i);
    expect(h.tombstone).toBeUndefined();
  });

  it('proceeds when the user never used the document rail (KSA/Nafath or unverified)', async () => {
    const h = harness({
      rail: null as any,
      identity: { redactPersonalData: async () => redacted({ supported: false, provider: 'UNCONFIGURED' }) },
    });
    await expect(h.svc.purgeUser('u1')).resolves.toBeDefined();
    expect(h.tombstone.recordsDeleted.identity.supported).toBe(false);
  });

  it('aborts the whole purge if the vendor refuses the redaction request', async () => {
    const h = harness({
      rail: 'DOCUMENT',
      identity: {
        redactPersonalData: async () => {
          throw new Error('Stripe: session is still processing');
        },
      },
    });
    await expect(h.svc.purgeUser('u1')).rejects.toThrow(/still processing/);
    expect(h.tombstone).toBeUndefined();
  });
});
