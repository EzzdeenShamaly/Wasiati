import { BadRequestException, NotFoundException } from '@nestjs/common';
import { DevEntitlementController } from './dev-entitlement.controller';
import { DevModule } from './dev.module';

/**
 * The dev comp grant hands out a paid tier for free, so — like the SMS outbox beside it —
 * the thing that matters is that it cannot exist outside local development. That gate is
 * the module's (pinned in dev-outbox-gating.spec.ts, which covers every controller
 * DevModule registers); these pin the controller's own behaviour, and that it is in fact
 * registered on that gated module rather than somewhere reachable.
 */
describe('DevEntitlementController', () => {
  const prismaWith = (count: number) => {
    const calls: any[] = [];
    return {
      calls,
      prisma: { user: { updateMany: async (args: any) => (calls.push(args), { count }) } } as any,
    };
  };

  it('grants the comp tier to the matching account', async () => {
    const { prisma, calls } = prismaWith(1);
    const ctl = new DevEntitlementController(prisma);
    await expect(ctl.grantComp({ email: 'Owner@Example.com', tier: 'PREMIUM' })).resolves.toEqual({
      email: 'owner@example.com',
      compTier: 'PREMIUM',
    });
    // Email normalised, and the grant is unbounded + attributed, matching an admin comp.
    expect(calls[0].where).toEqual({ email: 'owner@example.com' });
    expect(calls[0].data).toEqual({ compTier: 'PREMIUM', compExpiresAt: null, compGrantedBy: 'dev' });
  });

  it('defaults to the top tier, so a test can reach every gated feature', async () => {
    const { prisma, calls } = prismaWith(1);
    await new DevEntitlementController(prisma).grantComp({ email: 'a@b.test' });
    expect(calls[0].data.compTier).toBe('ULTIMATE');
  });

  it('rejects a missing email and an unknown tier rather than silently doing nothing', async () => {
    const { prisma, calls } = prismaWith(1);
    const ctl = new DevEntitlementController(prisma);
    await expect(ctl.grantComp({})).rejects.toBeInstanceOf(BadRequestException);
    await expect(ctl.grantComp({ email: '   ' })).rejects.toBeInstanceOf(BadRequestException);
    await expect(ctl.grantComp({ email: 'a@b.test', tier: 'FREEBIE' })).rejects.toThrow(/Unknown tier/);
    expect(calls).toHaveLength(0);
  });

  it('404s for an unknown account instead of reporting a grant that never happened', async () => {
    const { prisma } = prismaWith(0);
    await expect(new DevEntitlementController(prisma).grantComp({ email: 'nobody@x.test' })).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('lives on DevModule, so the production gate covers it', () => {
    const controllers = Reflect.getMetadata('controllers', DevModule) as unknown[];
    expect(controllers).toContain(DevEntitlementController);
  });
});
