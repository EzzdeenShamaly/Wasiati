import { BadRequestException } from '@nestjs/common';
import { Region, SubscriptionTier } from '@prisma/client';
import { PaymentsService } from './payments.service';

/**
 * A checkout that never starts must not keep the customer's credit.
 *
 * The debit happens at step 4, BEFORE the provider session is created, because the hosted
 * page needs a final amount — and CreditsService.consume commits its own transaction, so
 * nothing downstream can roll it back. Every path that returns credit (onPaymentDeclined,
 * onCheckoutExpired) is driven by a webhook for a session that EXISTS. When the session is
 * never created, no event can ever arrive and the debit is permanent.
 *
 * That is not a hypothetical: createHostedPayment throws whenever STRIPE_SECRET_KEY is
 * unset — the account's state today — and converts every transient Stripe failure into the
 * same BadRequestException. A customer holding referral credit who clicked Subscribe lost
 * it, saw an error, clicked again, and lost the rest: each attempt mints a fresh attemptId,
 * so the ledger's uniqueness key does not stop the second one.
 *
 * subscriptions.service.ts already does this for a declined renewal ("Give the credit back
 * — it was not actually spent"). Checkout was the sibling path that did not.
 */
describe('checkout: credit survives a provider failure', () => {
  const PLAN = {
    id: 'premium-US',
    tier: SubscriptionTier.PREMIUM,
    interval: 'YEAR',
    region: Region.US,
    displayName: 'Premium',
    active: true,
    currency: 'USD',
    unitAmount: 20000,
  };

  function makeService(opts: { creditMinor: number; providerThrows?: Error }) {
    const grants: any[] = [];
    const consumes: any[] = [];
    const prisma: any = {
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findMany: async () => [PLAN] },
    };
    const credits: any = {
      consume: async (p: any) => {
        consumes.push(p);
        return Math.min(opts.creditMinor, p.requestedMinor);
      },
      grant: async (p: any) => {
        grants.push(p);
        return { granted: true };
      },
    };
    const provider: any = {
      createHostedPayment: async () => {
        if (opts.providerThrows) throw opts.providerThrows;
        return { redirectUrl: 'https://pay.example/x', sessionId: 'cs_1' };
      },
    };
    const svc = new PaymentsService(
      { get: () => undefined } as any,
      prisma,
      {} as any,
      credits,
      { pendingDiscountPercent: async () => 0 } as any,
      { applyToAmount: async () => ({ amountMinor: PLAN.unitAmount, promotionId: null }) } as any,
      { record: async () => undefined } as any,
      provider,
    );
    return { svc, grants, consumes };
  }

  const checkout = (svc: PaymentsService) =>
    svc.createCheckoutSession({
      userId: 'u1',
      tier: SubscriptionTier.PREMIUM,
      interval: 'YEAR',
      successUrl: 'https://app.wasiati.com/s',
      cancelUrl: 'https://app.wasiati.com/c',
    });

  it('RETURNS the credit when the provider is not configured', async () => {
    // The literal message StripeProvider.client() throws with no STRIPE_SECRET_KEY.
    const { svc, grants, consumes } = makeService({
      creditMinor: 2500,
      providerThrows: new BadRequestException('Payments are not configured on this environment.'),
    });

    await expect(checkout(svc)).rejects.toThrow(/not configured/i);

    expect(consumes).toHaveLength(1);
    expect(grants).toHaveLength(1);
    expect(grants[0]).toMatchObject({ userId: 'u1', amountMinor: 2500, currency: 'USD' });
  });

  it('returns it on a TRANSIENT provider error too — every failure looks the same here', async () => {
    const { svc, grants } = makeService({
      creditMinor: 2500,
      providerThrows: new BadRequestException('Payment provider error.'),
    });
    await expect(checkout(svc)).rejects.toThrow(/provider error/i);
    expect(grants[0].amountMinor).toBe(2500);
  });

  // The debit and the reversal must be the same ledger pair, or a webhook that somehow
  // arrives later for this attempt would return the credit a SECOND time.
  it('keys the reversal to the SAME attemptId as the debit', async () => {
    const { svc, grants, consumes } = makeService({
      creditMinor: 2500,
      providerThrows: new BadRequestException('Payment provider error.'),
    });
    await expect(checkout(svc)).rejects.toThrow();
    expect(grants[0].sourceId).toBe(consumes[0].sourceId);
    expect(consumes[0].sourceType).toBe('CheckoutAttempt');
    expect(grants[0].sourceType).toBe('CheckoutCreditReturn');
  });

  it('still throws — the customer must not be told a dead checkout succeeded', async () => {
    const { svc } = makeService({
      creditMinor: 2500,
      providerThrows: new BadRequestException('Payments are not configured on this environment.'),
    });
    await expect(checkout(svc)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('grants NOTHING when there was no credit to lose', async () => {
    const { svc, grants } = makeService({
      creditMinor: 0,
      providerThrows: new BadRequestException('Payment provider error.'),
    });
    await expect(checkout(svc)).rejects.toThrow();
    expect(grants).toEqual([]); // an empty reversal row would be noise in the ledger
  });

  it('does not touch the credit on the happy path', async () => {
    const { svc, grants } = makeService({ creditMinor: 2500 });
    await expect(checkout(svc)).resolves.toMatchObject({ checkoutUrl: 'https://pay.example/x' });
    expect(grants).toEqual([]);
  });
});
