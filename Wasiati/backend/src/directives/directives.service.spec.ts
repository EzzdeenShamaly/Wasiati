import { BadRequestException } from '@nestjs/common';
import { DirectivesService } from './directives.service';

/**
 * Save-is-sign semantics for the beyond-the-will directives (POA / HCD).
 * Mocked Prisma + AuditService, no DB — mirrors heir-contacts.service.spec.
 */
describe('DirectivesService', () => {
  const USER = 'user-owner';

  function make() {
    const prisma = {
      directiveDocument: {
        findMany: jest.fn().mockResolvedValue([]),
        upsert: jest.fn().mockImplementation(({ where, create }: any) =>
          Promise.resolve({ id: 'dd1', ...where.userId_type, ...create })),
      },
    } as any;
    const audit = { log: jest.fn().mockResolvedValue(undefined) } as any;
    return { service: new DirectivesService(prisma, audit), prisma, audit };
  }

  const agent = { agentName: 'Fatima Al-Rashid', agentPhone: '+1 555 010 2030', agentEmail: 'fatima.r@gmail.com' };

  it('lists only the caller’s documents', async () => {
    const { service, prisma } = make();
    await service.list(USER);
    expect(prisma.directiveDocument.findMany).toHaveBeenCalledWith({
      where: { userId: USER },
      orderBy: { type: 'asc' },
    });
  });

  describe('save (POA)', () => {
    it('upserts by (userId, type) and signs in the same step', async () => {
      const { service, prisma, audit } = make();
      const doc = await service.save(USER, 'POA' as any, { ...agent, agentName: '  Fatima Al-Rashid  ' });
      const call = prisma.directiveDocument.upsert.mock.calls[0][0];
      expect(call.where).toEqual({ userId_type: { userId: USER, type: 'POA' } });
      expect(call.create).toMatchObject({ ...agent, userId: USER, type: 'POA', status: 'SIGNED', wishes: null });
      expect(call.update.signedAt).toBeInstanceOf(Date);
      expect(doc.status).toBe('SIGNED');
      expect(audit.log).toHaveBeenCalledWith(expect.objectContaining({ action: 'directive.sign', actorId: USER }));
    });

    it('refuses a blank agent field — the document cannot execute half-filled', async () => {
      const { service, prisma } = make();
      await expect(service.save(USER, 'POA' as any, { ...agent, agentPhone: '   ' }))
        .rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.directiveDocument.upsert).not.toHaveBeenCalled();
    });

    it('ignores wishes on a POA rather than storing them', async () => {
      const { service, prisma } = make();
      await service.save(USER, 'POA' as any, { ...agent, wishes: 'not a POA field' });
      expect(prisma.directiveDocument.upsert.mock.calls[0][0].create.wishes).toBeNull();
    });
  });

  describe('save (HCD)', () => {
    it('requires treatment wishes', async () => {
      const { service, prisma } = make();
      await expect(service.save(USER, 'HCD' as any, { ...agent, wishes: '' }))
        .rejects.toBeInstanceOf(BadRequestException);
      expect(prisma.directiveDocument.upsert).not.toHaveBeenCalled();
    });

    it('stores the wishes and signs', async () => {
      const { service, prisma } = make();
      await service.save(USER, 'HCD' as any, { ...agent, wishes: 'no prolonged life support' });
      expect(prisma.directiveDocument.upsert.mock.calls[0][0].create).toMatchObject({
        type: 'HCD',
        wishes: 'no prolonged life support',
        status: 'SIGNED',
      });
    });
  });
});
