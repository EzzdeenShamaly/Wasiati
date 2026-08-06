import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { HeirContactsService } from './heir-contacts.service';

/**
 * Owner-scoping + draft-only editability for the heir registry (create-flow
 * step 2). Uses a mocked Prisma so no DB is required — mirrors wills.service.spec.
 */
describe('HeirContactsService', () => {
  const OWNER = 'user-owner';
  const OTHER = 'user-attacker';

  function make(will: any, rows: any[] = []) {
    const prisma = {
      will: { findUnique: jest.fn().mockResolvedValue(will) },
      willHeirContact: {
        findMany: jest.fn().mockResolvedValue(rows),
        create: jest.fn().mockImplementation(({ data }: any) => Promise.resolve({ id: 'hc1', ...data })),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
        findUniqueOrThrow: jest.fn().mockImplementation(({ where }: any) => Promise.resolve({ id: where.id, name: 'Yusuf' })),
      },
    } as any;
    return { service: new HeirContactsService(prisma), prisma };
  }

  const draft = { ownerId: OWNER, status: 'DRAFT', locked: false };

  describe('list', () => {
    it('returns the roster to its owner', async () => {
      const { service } = make(draft, [{ id: 'hc1', name: 'Yusuf' }]);
      await expect(service.list('w1', OWNER)).resolves.toEqual([{ id: 'hc1', name: 'Yusuf' }]);
    });

    it('hides another user’s will behind NotFound', async () => {
      const { service } = make(draft);
      await expect(service.list('w1', OTHER)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('create', () => {
    it('persists a row for the owner, trimming blanks to null', async () => {
      const { service, prisma } = make(draft);
      const row = await service.create('w1', OWNER, { relation: 'son', name: '  Yusuf  ', phone: '', isMinor: true });
      expect(prisma.willHeirContact.create).toHaveBeenCalledWith({
        data: { willId: 'w1', relation: 'son', name: 'Yusuf', phone: null, email: null, isMinor: true },
      });
      expect(row).toMatchObject({ relation: 'son', name: 'Yusuf' });
    });

    it('refuses to add to a will the caller does not own', async () => {
      const { service, prisma } = make(draft);
      await expect(service.create('w1', OTHER, { relation: 'son' })).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.willHeirContact.create).not.toHaveBeenCalled();
    });

    it('refuses to edit a sealed (non-draft) will', async () => {
      const { service, prisma } = make({ ownerId: OWNER, status: 'SEALED', locked: false });
      await expect(service.create('w1', OWNER, { relation: 'son' })).rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.willHeirContact.create).not.toHaveBeenCalled();
    });
  });

  describe('update', () => {
    it('scopes the update to (id, willId)', async () => {
      const { service, prisma } = make(draft);
      await service.update('w1', OWNER, 'hc1', { phone: '+966 55 123 4567' });
      expect(prisma.willHeirContact.updateMany).toHaveBeenCalledWith({
        where: { id: 'hc1', willId: 'w1' },
        data: { phone: '+966 55 123 4567' },
      });
    });

    it('404s when the row is not on this will', async () => {
      const { service, prisma } = make(draft);
      prisma.willHeirContact.updateMany.mockResolvedValueOnce({ count: 0 });
      await expect(service.update('w1', OWNER, 'ghost', { name: 'x' })).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('remove', () => {
    it('deletes the owner’s row', async () => {
      const { service, prisma } = make(draft);
      await expect(service.remove('w1', OWNER, 'hc1')).resolves.toEqual({ deleted: true });
      expect(prisma.willHeirContact.deleteMany).toHaveBeenCalledWith({ where: { id: 'hc1', willId: 'w1' } });
    });

    it('refuses for a non-owner', async () => {
      const { service } = make(draft);
      await expect(service.remove('w1', OTHER, 'hc1')).rejects.toBeInstanceOf(NotFoundException);
    });
  });
});
