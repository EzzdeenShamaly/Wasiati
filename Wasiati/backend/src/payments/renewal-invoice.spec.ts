import { Region, SubscriptionTier } from '@prisma/client';
import { SubscriptionsService } from './subscriptions.service';
import { PaymentsService } from './payments.service';

/**
 * A renewal must leave exactly ONE correct receipt.
 *
 * The trap: a renewal is a confirmed off-session PaymentIntent, and Stripe fires
 * `payment_intent.succeeded` for it — so the webhook races the renewal job to
 * record the same payment. They dedupe on the payment id, so only one invoice is
 * written, which means whichever wins must produce the SAME invoice. The renewal
 * charge therefore carries the credit/total in its metadata; without it a webhook
 * that landed first recorded the CARD amount as the total and silently dropped the
 * "paid from account credit" line.
 */
describe('renewal invoices', () => {
  const plan = {
    id: 'p1',
    tier: SubscriptionTier.PREMIUM,
    interval: 'MONTH',
    region: Region.US,
    displayName: 'Premium',
    unitAmount: 1900,
    currency: 'USD',
    active: true,
  };

  const sub = {
    id: 's1',
    userId: 'u1',
    tier: SubscriptionTier.PREMIUM,
    interval: 'MONTH' as const,
    status: 'ACTIVE',
    currentPeriodEnd: new Date('2026-07-01T00:00:00Z'),
    cancelAtPeriodEnd: false,
    paymentInstrumentId: 'cus_1|pm_1',
    failedPaymentCount: 0,
  };

  /** Renewal job wired to a provider that approves, capturing the charge metadata. */
  const makeRenewal = (creditApplied: number) => {
    const charges: any[] = [];
    const recorded: any[] = [];
    const prisma: any = {
      subscription: { findMany: async () => [sub], update: async () => sub },
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findFirst: async () => plan },
    };
    const credits: any = { consume: async () => creditApplied, grant: async () => undefined };
    const invoices: any = { record: async (d: any) => recorded.push(d) };
    const provider: any = {
      chargeStoredInstrument: async (req: any) => {
        charges.push(req);
        return { approved: true, providerPaymentId: 'pi_renew_1' };
      },
    };
    const svc = new SubscriptionsService(prisma, {} as any, credits, invoices, provider);
    return { svc, charges, recorded };
  };

  it('records ONE invoice for the renewal, keyed on the payment id', async () => {
    const { svc, recorded } = makeRenewal(0);
    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));

    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({
      idempotencyKey: 'pi_renew_1', // the payment id — so the webhook's copy dedupes against it
      providerPaymentId: 'pi_renew_1',
      amountMinor: 1900,
      currency: 'USD',
      creditAppliedMinor: 0,
    });
  });

  it('the invoice total is the FULL price, with the credit part called out', async () => {
    // $19 plan, $4 of credit → $15 on the card. The receipt must still say 19.
    const { svc, recorded, charges } = makeRenewal(400);
    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));

    expect(charges[0].amountMinor).toBe(1500); // the card is charged the remainder
    expect(recorded[0]).toMatchObject({ amountMinor: 1900, creditAppliedMinor: 400 });
  });

  it('carries the credit/total in the CHARGE metadata, so the racing webhook writes the same invoice', async () => {
    const { svc, charges } = makeRenewal(400);
    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));

    // Without these the webhook's onPaymentApproved has no idea credit was used.
    expect(charges[0].metadata).toMatchObject({
      userId: 'u1',
      creditAppliedMinor: '400',
      basisMinor: '1900',
      basisCurrency: 'USD',
      description: 'Wasiati Premium renewal',
    });
  });

  it('the webhook, fed that metadata, produces an IDENTICAL invoice', async () => {
    // Prove the two writers agree — this is what makes the race harmless.
    const { svc, charges, recorded } = makeRenewal(400);
    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));
    const fromRenewalJob = recorded[0];

    const webhookInvoices: any[] = [];
    const payments = new PaymentsService(
      { get: () => undefined } as any,
      {
        subscription: {
          findFirst: async () => sub,
          update: async () => sub,
          create: async () => sub,
          // fulfil's supersede sweep — nothing else to supersede in this fixture.
          updateMany: async () => ({ count: 0 }),
        },
      } as any,
      {} as any,
      {} as any,
      { handleQualifyingPurchase: async () => undefined } as any,
      {} as any,
      { record: async (d: any) => webhookInvoices.push(d) } as any,
      {} as any,
    );

    // What Stripe sends for the very PaymentIntent the renewal just confirmed.
    await (payments as any).onPaymentApproved({
      id: 'evt_1',
      type: 'payment_approved',
      providerPaymentId: 'pi_renew_1',
      amountMinor: 1500, // the CARD amount
      currency: 'USD',
      metadata: charges[0].metadata,
    });

    expect(webhookInvoices).toHaveLength(1);
    const fromWebhook = webhookInvoices[0];
    // Same key → one row survives; same numbers → it does not matter which.
    expect(fromWebhook.idempotencyKey).toBe(fromRenewalJob.idempotencyKey);
    expect(fromWebhook.amountMinor).toBe(fromRenewalJob.amountMinor);
    expect(fromWebhook.creditAppliedMinor).toBe(fromRenewalJob.creditAppliedMinor);
    expect(fromWebhook.currency).toBe(fromRenewalJob.currency);
    expect(fromWebhook.description).toBe(fromRenewalJob.description);
  });

  it('a renewal covered entirely by credit still gets a receipt (no provider payment, no webhook)', async () => {
    const { svc, charges, recorded } = makeRenewal(1900);
    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));

    expect(charges).toHaveLength(0); // nothing to charge
    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({
      idempotencyKey: 'renewal:s1:2026-07-01T00:00:00.000Z', // deterministic per period
      amountMinor: 1900,
      creditAppliedMinor: 1900,
    });
  });

  it('a DECLINED renewal writes no invoice — we only receipt money we took', async () => {
    const recorded: any[] = [];
    const prisma: any = {
      subscription: { findMany: async () => [sub], update: async () => sub },
      user: { findUnique: async () => ({ id: 'u1', email: 'a@b.com', region: Region.US }) },
      pricingPlan: { findFirst: async () => plan },
    };
    const svc = new SubscriptionsService(
      prisma,
      { sendEmail: async () => undefined } as any,
      { consume: async () => 0, grant: async () => undefined } as any,
      { record: async (d: any) => recorded.push(d) } as any,
      { chargeStoredInstrument: async () => ({ approved: false, declineReason: 'Card declined' }) } as any,
    );

    await svc.runBillingCycle(new Date('2026-07-01T04:00:00Z'));
    expect(recorded).toHaveLength(0);
  });
});
