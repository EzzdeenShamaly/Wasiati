import { EntitlementsService } from './entitlements.service';

function mockPrisma(user: any, subs: any = null) {
  const list = subs == null ? [] : Array.isArray(subs) ? subs : [subs];
  return {
    user: { findUnique: jest.fn().mockResolvedValue(user) },
    // Honours the status filter rather than returning everything: WHICH statuses resolve()
    // asks for is the entire dunning-grace decision (ACTIVE + PAST_DUE, never CANCELED),
    // and a double that ignored the where would pass with that decision broken either way.
    subscription: {
      findMany: jest.fn().mockImplementation(({ where }: any = {}) => {
        const allowed = where?.status?.in ?? (where?.status ? [where.status] : null);
        return Promise.resolve(allowed ? list.filter((s: any) => allowed.includes(s.status)) : list);
      }),
    },
  } as any;
}

describe('EntitlementsService', () => {
  it('grants ADMIN full access without a subscription', async () => {
    const svc = new EntitlementsService(mockPrisma({ role: 'ADMIN', compTier: null, compExpiresAt: null }));
    const e = await svc.resolve('u');
    expect(e.source).toBe('admin');
    expect(e.tier).toBe('ULTIMATE');
    expect(e.isAdmin).toBe(true);
    expect(e.features.aiIntake).toBe(true);
    expect(e.features.burialPlanning).toBe(true);
  });

  it('honors a non-expired comp grant (PREMIUM => aiIntake, not burial)', async () => {
    const future = new Date(Date.now() + 86_400_000);
    const svc = new EntitlementsService(mockPrisma({ role: 'USER', compTier: 'PREMIUM', compExpiresAt: future }));
    const e = await svc.resolve('u');
    expect(e.source).toBe('comp');
    expect(e.tier).toBe('PREMIUM');
    expect(e.features.aiIntake).toBe(true);
    expect(e.features.burialPlanning).toBe(false);
  });

  it('ignores an expired comp grant', async () => {
    const past = new Date(Date.now() - 86_400_000);
    const svc = new EntitlementsService(mockPrisma({ role: 'USER', compTier: 'PREMIUM', compExpiresAt: past }));
    const e = await svc.resolve('u');
    expect(e.source).toBe('none');
    expect(e.features.aiIntake).toBe(false);
  });

  it('falls back to an active subscription tier', async () => {
    const svc = new EntitlementsService(
      mockPrisma(
        { role: 'USER', compTier: null, compExpiresAt: null },
        { tier: 'STANDARD', status: 'ACTIVE', currentPeriodEnd: null },
      ),
    );
    const e = await svc.resolve('u');
    expect(e.source).toBe('subscription');
    expect(e.tier).toBe('STANDARD');
    expect(e.features.vault).toBe(true);
    expect(e.features.aiIntake).toBe(false);
  });

  it('picks the HIGHEST tier among active subscriptions (one-time Basic must not downgrade)', async () => {
    const svc = new EntitlementsService(
      mockPrisma({ role: 'USER', compTier: null, compExpiresAt: null }, [
        { tier: 'STANDARD', status: 'ACTIVE', currentPeriodEnd: new Date() },
        { tier: 'BASIC', status: 'ACTIVE', currentPeriodEnd: null }, // one-time, newer row
      ]),
    );
    const e = await svc.resolve('u');
    expect(e.tier).toBe('STANDARD');
    expect(e.features.vault).toBe(true);
  });

  /**
   * The dunning grace, honoured where access is actually decided.
   *
   * subscriptions.service.ts says it in words: "Access is not revoked the instant a card
   * fails — people's cards expire, and this is a will." A declined renewal sets PAST_DUE
   * and the daily cron retries up to MAX_FAILURES before CANCELING — so PAST_DUE is, by
   * definition, inside that grace window. resolve() matched ACTIVE alone, which revoked
   * the tier at the FIRST decline: the vault sealed itself and the paywall dropped on a
   * paying customer whose card had simply expired, while the same codebase's billing cron
   * was still planning to retry their card in the morning.
   */
  it('keeps a PAST_DUE subscriber entitled — dunning retries, it does not revoke', async () => {
    const svc = new EntitlementsService(
      mockPrisma(
        { role: 'USER', compTier: null, compExpiresAt: null },
        { tier: 'STANDARD', status: 'PAST_DUE', currentPeriodEnd: new Date() },
      ),
    );
    const e = await svc.resolve('u');
    expect(e.source).toBe('subscription');
    expect(e.tier).toBe('STANDARD');
    expect(e.features.vault).toBe(true);
  });

  // Where dunning ends, access ends. CANCELED is the cron GIVING UP (MAX_FAILURES), and a
  // canceled row must confer nothing — this is the other edge of the same decision.
  it('confers nothing for a CANCELED subscription — the grace window has an end', async () => {
    const svc = new EntitlementsService(
      mockPrisma(
        { role: 'USER', compTier: null, compExpiresAt: null },
        { tier: 'STANDARD', status: 'CANCELED', currentPeriodEnd: new Date() },
      ),
    );
    const e = await svc.resolve('u');
    expect(e.source).toBe('none');
    expect(e.tier).toBeNull();
    expect(e.features.vault).toBe(false);
  });

  it('returns none for a free user', async () => {
    const svc = new EntitlementsService(mockPrisma({ role: 'USER', compTier: null, compExpiresAt: null }));
    const e = await svc.resolve('u');
    expect(e.source).toBe('none');
    expect(e.tier).toBeNull();
  });

  it('hasFeature reflects entitlements (admin bypass)', async () => {
    const svc = new EntitlementsService(mockPrisma({ role: 'ADMIN', compTier: null, compExpiresAt: null }));
    expect(await svc.hasFeature('u', 'burialPlanning')).toBe(true);
  });
});
