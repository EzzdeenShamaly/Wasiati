import { BadRequestException } from '@nestjs/common';
import { ContentService } from './content.service';

/**
 * The Content tab serves live-editable UI copy, including the legal disclaimer, so
 * two invariants matter:
 *   1. a published change ALWAYS writes an audit revision (they move together);
 *   2. both EN and AR are required — a half-translated override would show the wrong
 *      language to half the users.
 */
function makeDb() {
  const strings = new Map<string, any>();
  const revisions: any[] = [];

  const prisma: any = {
    contentString: {
      findMany: async ({ where }: any = {}) => {
        let rows = [...strings.values()];
        if (where?.published !== undefined) rows = rows.filter((r) => r.published === where.published);
        return rows;
      },
      findUnique: async ({ where }: any) => strings.get(where.key) ?? null,
      upsert: async ({ where, create, update }: any) => {
        const existing = strings.get(where.key);
        const row = existing ? { ...existing, ...update } : { ...create };
        strings.set(where.key, row);
        return row;
      },
      delete: async ({ where }: any) => {
        const r = strings.get(where.key);
        strings.delete(where.key);
        return r;
      },
    },
    contentRevision: {
      create: async ({ data }: any) => {
        const r = { id: `rev${revisions.length + 1}`, createdAt: new Date(), ...data };
        revisions.push(r);
        return r;
      },
      findMany: async ({ where }: any) => revisions.filter((r) => r.key === where.key),
    },
    // The service relies on $transaction([...]) being atomic; the double runs the
    // ops in order and returns their results, which is enough to assert on.
    $transaction: async (ops: Promise<any>[]) => Promise.all(ops),
  };

  return { prisma, strings, revisions };
}

describe('ContentService', () => {
  describe('upsert', () => {
    it('publishing a string also writes an audit revision, atomically', async () => {
      const db = makeDb();
      const svc = new ContentService(db.prisma);

      await svc.upsert('prBasicSub', { en: 'One will, one time', ar: 'وصية واحدة، مرة واحدة' }, 'admin1');

      expect(db.strings.get('prBasicSub')).toMatchObject({ valueEn: 'One will, one time', published: true });
      expect(db.revisions).toHaveLength(1);
      expect(db.revisions[0]).toMatchObject({ key: 'prBasicSub', editedBy: 'admin1' });
    });

    it('a second edit appends a SECOND revision — history is never overwritten', async () => {
      const db = makeDb();
      const svc = new ContentService(db.prisma);

      await svc.upsert('k', { en: 'v1', ar: 'ن1' }, 'admin1');
      await svc.upsert('k', { en: 'v2', ar: 'ن2' }, 'admin2');

      expect(db.strings.get('k').valueEn).toBe('v2');
      expect(db.revisions).toHaveLength(2);
      expect(db.revisions.map((r) => r.editedBy)).toEqual(['admin1', 'admin2']);
    });

    it('REQUIRES both English and Arabic — never a half-translated override', async () => {
      const svc = new ContentService(makeDb().prisma);
      await expect(svc.upsert('k', { en: 'only english', ar: '' }, 'a')).rejects.toThrow(BadRequestException);
      await expect(svc.upsert('k', { en: '  ', ar: 'عربي فقط' }, 'a')).rejects.toThrow(/Arabic/i);
    });

    it('rejects an empty key', async () => {
      const svc = new ContentService(makeDb().prisma);
      await expect(svc.upsert('  ', { en: 'x', ar: 'س' }, 'a')).rejects.toThrow(/key/i);
    });

    it('trims surrounding whitespace before storing', async () => {
      const db = makeDb();
      await new ContentService(db.prisma).upsert('k', { en: '  hi  ', ar: '  مرحبا  ' }, 'a');
      expect(db.strings.get('k').valueEn).toBe('hi');
      expect(db.strings.get('k').valueAr).toBe('مرحبا');
    });

    it('can save an explicit draft, which is kept OUT of the public overrides', async () => {
      const db = makeDb();
      const svc = new ContentService(db.prisma);
      await svc.upsert('draftKey', { en: 'wip', ar: 'مسودة', published: false }, 'a');
      await svc.upsert('liveKey', { en: 'live', ar: 'منشور' }, 'a');

      const overrides = await svc.publishedOverrides();
      expect(overrides).toHaveProperty('liveKey');
      expect(overrides).not.toHaveProperty('draftKey');
    });
  });

  describe('publishedOverrides', () => {
    it('returns { key: { en, ar } } for published strings only', async () => {
      const db = makeDb();
      const svc = new ContentService(db.prisma);
      await svc.upsert('a', { en: 'A', ar: 'أ' }, 'x');

      expect(await svc.publishedOverrides()).toEqual({ a: { en: 'A', ar: 'أ' } });
    });
  });

  describe('remove', () => {
    it('removes an override so the app reverts to its bundled string', async () => {
      const db = makeDb();
      const svc = new ContentService(db.prisma);
      await svc.upsert('k', { en: 'v', ar: 'ن' }, 'a');

      expect(await svc.remove('k', 'admin1')).toEqual({ removed: true });
      expect(db.strings.has('k')).toBe(false);
    });

    it('removing a non-existent key is a no-op, not an error', async () => {
      const svc = new ContentService(makeDb().prisma);
      expect(await svc.remove('nope', 'admin1')).toEqual({ removed: false });
    });
  });
});
