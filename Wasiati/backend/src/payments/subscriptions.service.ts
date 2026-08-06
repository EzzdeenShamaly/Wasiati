import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PriceInterval, Subscription } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreditsService } from '../credits/credits.service';
import { PAYMENT_PROVIDER, PaymentProviderPort } from './payment-provider.interface';
import { convertToFallbackMinor, resolveBillingCurrency } from '../common/geo.util';
import { InvoicesService } from './invoices.service';
import { CRON_LOCKS, withCronLock } from '../common/cron-lock';

/**
 * The subscription engine.
 *
 * We deliberately run the billing cycle ourselves rather than handing it to
 * Stripe Billing — the PSP only moves money, so it stays swappable.
 * Once a day we find subscriptions whose period has ended and
 * either cancel them (if the user asked) or charge the stored card as a
 * merchant-initiated transaction.
 *
 * Dunning: a declined renewal moves the subscription to PAST_DUE and retries on
 * subsequent runs. After MAX_FAILURES it is CANCELED. Access is not revoked the
 * instant a card fails — people's cards expire, and this is a will.
 */
@Injectable()
export class SubscriptionsService {
  private readonly logger = new Logger(SubscriptionsService.name);

  /** Declines tolerated before we give up and cancel. */
  private static readonly MAX_FAILURES = 4;

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
    private credits: CreditsService,
    private invoices: InvoicesService,
    @Inject(PAYMENT_PROVIDER) private provider: PaymentProviderPort,
  ) {}

  private nextPeriodEnd(from: Date, interval: PriceInterval): Date {
    const d = new Date(from);
    if (interval === 'YEAR') d.setUTCFullYear(d.getUTCFullYear() + 1);
    else d.setUTCMonth(d.getUTCMonth() + 1);
    return d;
  }

  /** Runs daily. Kept idempotent so a double-run cannot double-charge. */
  @Cron(CronExpression.EVERY_DAY_AT_4AM)
  async runBillingCycleCron() {
    // The advisory lock is what makes >1 task safe: without it, every running task
    // fires this cron and every renewal is CHARGED once per task. The lock lives in
    // the same database the job mutates and releases itself if we crash mid-run.
    await withCronLock(this.prisma, CRON_LOCKS.subscriptionRenewals, 'billing-cycle', () => this.runBillingCycle());
  }

  async runBillingCycle(now: Date = new Date()) {
    const due = await this.prisma.subscription.findMany({
      where: {
        status: { in: ['ACTIVE', 'PAST_DUE'] },
        currentPeriodEnd: { lte: now },
      },
    });

    let renewed = 0;
    let canceled = 0;
    let failed = 0;

    for (const sub of due) {
      try {
        if (sub.cancelAtPeriodEnd) {
          await this.finaliseCancellation(sub);
          canceled++;
          continue;
        }
        const ok = await this.renew(sub, now);
        if (ok) renewed++;
        else failed++;
      } catch (e) {
        this.logger.error(`Billing cycle failed for subscription ${sub.id}: ${(e as Error).message}`);
      }
    }

    if (due.length) {
      this.logger.log(`Billing cycle: ${due.length} due → ${renewed} renewed, ${failed} failed, ${canceled} canceled.`);
    }
    return { due: due.length, renewed, failed, canceled };
  }

  private async finaliseCancellation(sub: Subscription) {
    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: { status: 'CANCELED', canceledAt: sub.canceledAt ?? new Date() },
    });
    this.logger.log(`Subscription ${sub.id} canceled at period end.`);
  }

  /**
   * Charges one renewal. Applies any account credit FIRST, so a referral reward
   * genuinely reduces the next invoice rather than sitting unused.
   */
  private async renew(sub: Subscription, now: Date): Promise<boolean> {
    if (!sub.interval) {
      this.logger.error(`Subscription ${sub.id} has no interval; skipping.`);
      return false;
    }

    // MUST scope by the user's region: the same tier+interval exists in every
    // region at a different price and currency. Without this a Qatari subscriber
    // could be renewed at the US price.
    const user = await this.prisma.user.findUnique({ where: { id: sub.userId }, select: { region: true } });
    if (!user) {
      this.logger.error(`Subscription ${sub.id} has no user; skipping.`);
      return false;
    }

    const plan = await this.prisma.pricingPlan.findFirst({
      where: { tier: sub.tier, interval: sub.interval, region: user.region, active: true },
    });
    if (!plan) {
      this.logger.error(`No active ${user.region} plan for ${sub.tier}/${sub.interval}; skipping ${sub.id}.`);
      return false;
    }

    if (!sub.paymentInstrumentId) {
      await this.markFailed(sub, 'No stored payment method');
      return false;
    }

    // Same currency rule as checkout: charge the user's own currency, converting
    // (never relabelling) if the provider cannot process it.
    const billingCurrency = resolveBillingCurrency(plan.region);
    const payable =
      billingCurrency === plan.currency
        ? plan.unitAmount
        : convertToFallbackMinor(plan.unitAmount, plan.currency);

    // Identifies THIS renewal PERIOD — deterministic, so a double run of the daily job
    // writes one invoice for the period rather than two.
    const periodId = `${sub.id}:${sub.currentPeriodEnd?.toISOString() ?? now.toISOString()}`;

    // Identifies this ATTEMPT at that period. AccountCredit is unique on
    // (sourceType, sourceId, userId), and the credit consume used to key on periodId
    // alone — which wedged any subscriber holding credit whose card was failing:
    //
    //   day 1  consume('Renewal', periodId) debits; the card declines; the credit is
    //          granted back under 'RenewalFailed'; markFailed sets PAST_DUE.
    //   day 2  the period has NOT advanced, so the same periodId is computed and the
    //          same debit row is attempted — Prisma throws P2002, BEFORE
    //          chargeStoredInstrument and before markFailed. runBillingCycle only logs.
    //
    // The card was therefore never retried, failedPaymentCount never advanced, dunning
    // never escalated, and the subscription neither renewed nor cancelled: stuck
    // forever, crashing nightly, in silence. It needed credit AND a failing card, which
    // is why no test caught it.
    //
    // failedPaymentCount is the natural attempt discriminator and advances on every
    // failure, so each retry now writes its own ledger row — which is what the ledger
    // always meant, since every attempt has its own paired reversal.
    //
    // A genuine concurrent double-run (two workers both reading the same count before
    // either markFailed lands) still collides on P2002, and there that is the CORRECT
    // protection: it stops one credit being consumed twice. The cycle's catch skips
    // that subscription for that run and the next run proceeds, because the winner's
    // markFailed has moved the counter on. Failing is only wrong when it repeats.
    const attemptId = `${periodId}:a${sub.failedPaymentCount}`;

    // Credit first — it may cover the whole renewal.
    const applied = await this.credits.consume({
      userId: sub.userId,
      requestedMinor: payable,
      currency: billingCurrency,
      description: `Applied to ${plan.tier} renewal`,
      sourceType: 'Renewal',
      sourceId: attemptId,
    });
    const amountDue = Math.max(0, payable - applied);

    if (amountDue === 0) {
      await this.markRenewed(sub, now, plan.interval);
      // No provider payment, so no webhook will ever write this receipt.
      await this.invoices.record({
        userId: sub.userId,
        idempotencyKey: `renewal:${periodId}`,
        description: `Wasiati ${plan.displayName} renewal`,
        amountMinor: payable,
        currency: billingCurrency,
        creditAppliedMinor: applied,
        tier: sub.tier,
        interval: plan.interval,
      });
      this.logger.log(`Subscription ${sub.id} renewed entirely from account credit.`);
      return true;
    }

    const description = `Wasiati ${plan.displayName} renewal`;
    const result = await this.provider.chargeStoredInstrument({
      userId: sub.userId,
      paymentInstrumentId: sub.paymentInstrumentId,
      amountMinor: amountDue,
      currency: billingCurrency,
      description,
      metadata: {
        userId: sub.userId,
        subscriptionId: sub.id,
        tier: sub.tier,
        interval: sub.interval,
        // A confirmed off-session PaymentIntent ALSO fires payment_intent.succeeded,
        // so the webhook races us to write this receipt. Both keep the same
        // idempotency key (the payment id), so only one invoice is written — but
        // whichever wins must produce the SAME one. Carrying the credit/total here
        // is what makes the webhook's version identical to ours; without it, a
        // webhook that landed first recorded the card amount as the total and lost
        // the "paid from account credit" line.
        creditAppliedMinor: String(applied),
        creditCurrency: billingCurrency,
        basisMinor: String(payable),
        basisCurrency: billingCurrency,
        description,
      },
    });

    if (!result.approved) {
      // Give the credit back — it was not actually spent.
      if (applied > 0) {
        await this.credits.grant({
          userId: sub.userId,
          amountMinor: applied,
          currency: billingCurrency,
          reason: 'MANUAL_ADJUSTMENT',
          description: 'Credit returned after a failed renewal',
          sourceType: 'RenewalFailed',
          // Paired with the debit's attemptId, so the ledger reads as matched
          // consume/reverse rows per attempt rather than a debit keyed on the period
          // and a refund keyed on a wall-clock instant that nothing else references.
          sourceId: attemptId,
        });
      }
      await this.markFailed(sub, result.declineReason ?? 'Card declined');
      return false;
    }

    await this.markRenewed(sub, now, plan.interval);
    // Record the receipt keyed on the payment id. The payment_intent.succeeded
    // webhook writes the same invoice under the same key (see the metadata above),
    // so exactly one is stored whichever arrives first — but we do not rely on the
    // webhook, because a renewal must appear in the invoice list even if the event
    // is delayed or dropped.
    await this.invoices.record({
      userId: sub.userId,
      idempotencyKey: result.providerPaymentId ?? `renewal:${periodId}`,
      description,
      amountMinor: payable,
      currency: billingCurrency,
      creditAppliedMinor: applied,
      tier: sub.tier,
      interval: plan.interval,
      providerPaymentId: result.providerPaymentId,
    });
    return true;
  }

  private async markRenewed(sub: Subscription, now: Date, interval: PriceInterval) {
    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: {
        status: 'ACTIVE',
        // Advance from the OLD period end, not from now, so a late job run does
        // not silently shorten the customer's paid period.
        currentPeriodEnd: this.nextPeriodEnd(sub.currentPeriodEnd ?? now, interval),
        failedPaymentCount: 0,
        lastPaymentAt: now,
      },
    });
  }

  private async markFailed(sub: Subscription, reason: string) {
    const failures = sub.failedPaymentCount + 1;
    const giveUp = failures >= SubscriptionsService.MAX_FAILURES;

    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: {
        status: giveUp ? 'CANCELED' : 'PAST_DUE',
        failedPaymentCount: failures,
        ...(giveUp ? { canceledAt: new Date() } : {}),
      },
    });

    const user = await this.prisma.user.findUnique({ where: { id: sub.userId } });
    if (user) {
      const body = giveUp
        ? `We could not renew your Wasiati ${sub.tier} plan after ${failures} attempts (${reason}). Your subscription has been cancelled — your sealed will remains safe. Update your card to resubscribe.`
        : `We could not take payment for your Wasiati ${sub.tier} plan (${reason}). We will retry. Please update your card to avoid interruption.`;
      await this.notifications
        .sendEmail(user.email, giveUp ? 'Wasiati: subscription cancelled' : 'Wasiati: payment failed', body)
        .catch((e) => this.logger.error(`Dunning email failed: ${(e as Error).message}`));
    }

    this.logger.warn(`Subscription ${sub.id} payment failed (${failures}/${SubscriptionsService.MAX_FAILURES}): ${reason}`);
  }
}
