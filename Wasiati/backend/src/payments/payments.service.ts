import { BadRequestException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CreditReason, PriceInterval, PricingPlan, Prisma, Region, SubscriptionTier } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreditsService } from '../credits/credits.service';
import { ReferralsService } from '../referrals/referrals.service';
import { PromotionsService } from '../commerce/promotions.service';
import { assertPurchasable } from '../commerce/plan-rules';
import { PAYMENT_PROVIDER, PaymentEvent, PaymentProviderPort, isRecurring } from './payment-provider.interface';
import { convertToFallbackMinor, resolveBillingCurrency } from '../common/geo.util';
import { InvoicesService } from './invoices.service';

/**
 * Payments, on Stripe (as a dumb PSP — no Stripe Billing).
 *
 * The provider only moves money. Everything a bundled PSP would give you for free
 * lives here or next door:
 *   · subscription lifecycle → SubscriptionsService (renewal job, dunning, cancel)
 *   · discounts              → PromotionsService (applied to the amount, not mirrored)
 *   · account credit         → CreditsService (our ledger, not a customer balance)
 *
 * Webhooks are idempotent via ProcessedPaymentEvent: a replayed event id is a no-op.
 */
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  /** The intervals that renew. A ONE_TIME row is a lifetime entitlement, not a billing cycle. */
  private static readonly RECURRING_INTERVALS: PriceInterval[] = ['MONTH', 'YEAR'];

  constructor(
    private config: ConfigService,
    private prisma: PrismaService,
    private notifications: NotificationsService,
    private credits: CreditsService,
    private referrals: ReferralsService,
    private promotions: PromotionsService,
    private invoices: InvoicesService,
    @Inject(PAYMENT_PROVIDER) private provider: PaymentProviderPort,
  ) {}

  /**
   * The checkout success/cancel URLs come back to the browser, so an unconstrained
   * value is an open-redirect. If PAYMENT_RETURN_HOSTS is set (comma-separated), the
   * URL must be https on one of those hosts. Unset = permissive (dev/local), and the
   * DTO already requires a well-formed URL.
   */
  private assertReturnUrl(url: string) {
    const allowed = this.config.get<string>('PAYMENT_RETURN_HOSTS');
    if (!allowed) return;
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      throw new BadRequestException('Invalid return URL.');
    }
    const hosts = allowed.split(',').map((h) => h.trim().toLowerCase());
    if (parsed.protocol !== 'https:' || !hosts.includes(parsed.host.toLowerCase())) {
      throw new BadRequestException('Return URL is not permitted.');
    }
  }

  /** Resolves exactly one plan — never guesses between monthly and annual. */
  private async resolvePlan(tier: SubscriptionTier, region: Region, interval?: PriceInterval): Promise<PricingPlan> {
    const candidates = await this.prisma.pricingPlan.findMany({
      where: { tier, region, active: true, ...(interval ? { interval } : {}) },
    });
    if (candidates.length === 0) throw new BadRequestException('This plan is not available for purchase yet.');
    if (candidates.length > 1) {
      throw new BadRequestException(
        'Several billing periods exist for this plan — specify `interval` (MONTH, YEAR or ONE_TIME).',
      );
    }
    return candidates[0];
  }

  /**
   * Starts a hosted checkout.
   *
   * Order of operations on the amount: plan price → promo discount → referral
   * discount → currency conversion → account credit. The promo and the referral
   * discount STACK, and they compound: the referral percentage is taken off the
   * already-promo-discounted figure, so 20% off plus a referred friend's 10% is
   * 28% off the list price, not 30%. Neither one suppresses the other.
   *
   * Credit is CONSUMED here because the hosted page needs a final amount;
   * the webhook returns it if the money never arrives — a declined payment
   * (payment_declined) or an abandoned session (checkout_expired), exactly once
   * per attempt either way.
   *
   * NOTE the absent `region` parameter: the buyer is signed in, so the region —
   * and therefore the currency and the price — is read from their ACCOUNT and the
   * client has no say. A client-supplied region here would let anyone pay the
   * cheapest market's price by editing one field.
   */
  async createCheckoutSession(params: {
    userId: string;
    tier: SubscriptionTier;
    interval?: PriceInterval;
    promoCode?: string;
    successUrl: string;
    cancelUrl: string;
  }) {
    const user = await this.prisma.user.findUnique({ where: { id: params.userId } });
    if (!user) throw new BadRequestException('User not found.');

    // The post-payment return URLs are echoed to the browser; constrain them to our
    // own hosts so a user can't turn checkout into an open-redirect/phishing pivot.
    this.assertReturnUrl(params.successUrl);
    this.assertReturnUrl(params.cancelUrl);

    const plan = await this.resolvePlan(params.tier, user.region, params.interval);

    // The (tier, interval) product rule, enforced where it counts. The app hides
    // Ultimate on the one-time cycle; this is what makes hiding it true.
    assertPurchasable(plan.tier, plan.interval);

    // 1. Promotion (validated + applied by us; there is no provider coupon object).
    const discounted = params.promoCode?.trim()
      ? await this.promotions.applyToAmount(params.promoCode.trim(), plan, user.id)
      : { amountMinor: plan.unitAmount, promotionId: null as string | null, rejectedReason: undefined };

    // A code the buyer actually typed and that we cannot honour is an ERROR, not a
    // silent full-price charge. The pricing page previews without a tier, so a
    // tier-restricted code (e.g. LAUNCH25, which excludes Basic) previewed as valid
    // and then quietly vanished at checkout — the customer was shown "25% off" and
    // billed 100% with nothing to explain it. Better to stop and say why.
    if (discounted.rejectedReason) throw new BadRequestException(discounted.rejectedReason);

    // 2. A referred friend gets their referral discount on top, but only on plans
    // that already carry a one-year commitment (annual / one-time).
    const referralDiscountPercent = await this.referrals.pendingDiscountPercent(user.id, plan.interval);
    const afterReferral =
      referralDiscountPercent > 0
        ? Math.round((discounted.amountMinor * (100 - referralDiscountPercent)) / 100)
        : discounted.amountMinor;

    // 3. Bill the user in their own currency. If the provider cannot process it
    // (e.g. QAR not yet enabled on the account), convert to USD rather than
    // relabelling — 72500 QAR-minor is ~$199, not $725.
    const billingCurrency = resolveBillingCurrency(plan.region);
    const payable =
      billingCurrency === plan.currency
        ? afterReferral
        : convertToFallbackMinor(afterReferral, plan.currency);

    // 4. Account credit, held and spent in the SAME currency we are charging.
    // This id identifies THIS checkout attempt in the credit ledger; it doubles as
    // the invoice key below, tying a credit-covered receipt to the ledger row that
    // paid for it.
    const attemptId = `${plan.id}:${Date.now()}`;
    const applied = await this.credits.consume({
      userId: user.id,
      requestedMinor: payable,
      currency: billingCurrency,
      description: `Applied to ${plan.tier} (${plan.interval})`,
      sourceType: 'CheckoutAttempt',
      sourceId: attemptId,
    });
    const amountDue = Math.max(0, payable - applied);

    const metadata: Record<string, string> = {
      userId: user.id,
      tier: plan.tier,
      region: plan.region,
      interval: plan.interval,
      planId: plan.id,
      // The credit-ledger id of THIS attempt. The decline/expiry handlers key the
      // credit RETURN on it, so one attempt gets its credit back exactly once no
      // matter how many events (a decline, then expiry of the same session) arrive.
      attemptId,
      creditAppliedMinor: String(applied),
      creditCurrency: billingCurrency,
      // The friend's first-year value that a referrer's 2.5% is computed from: the
      // committed price net of discounts, independent of how the friend funded it.
      // (Not `amountDue` — otherwise paying with account credit would silently
      // shrink someone else's commission.)
      basisMinor: String(payable),
      basisCurrency: billingCurrency,
      ...(referralDiscountPercent > 0 ? { referralDiscountPercent: String(referralDiscountPercent) } : {}),
      ...(discounted.promotionId ? { promotionId: discounted.promotionId } : {}),
    };

    // 5. Fully covered by credit — nothing to charge, so activate immediately.
    // The provider never sees this purchase, so there is no webhook: qualify the
    // referral here, or the same purchase would pay a commission only when a card
    // happened to be charged.
    if (amountDue === 0) {
      await this.fulfil({
        userId: user.id,
        tier: plan.tier,
        interval: plan.interval,
        planId: plan.id,
        paymentInstrumentId: undefined,
      });
      // The provider issues no receipt for a purchase it never saw, so record ours
      // — otherwise buying with credit leaves a blank in the customer's invoice
      // list. Keyed on the credit-ledger attempt id: one attempt, one invoice.
      await this.invoices.record({
        userId: user.id,
        idempotencyKey: `credit:${attemptId}`,
        description: this.planDescription(plan),
        amountMinor: payable,
        currency: billingCurrency,
        creditAppliedMinor: applied,
        tier: plan.tier,
        interval: plan.interval,
      });
      // The promo was REDEEMED — the discount set the very price the credit just settled —
      // so it counts against maxRedemptions here exactly as it does in onPaymentApproved.
      // This path never skipped it by accident of wording: a 100%-off code ALWAYS lands
      // here (the discount itself makes amountDue 0, no card, no webhook), so a capped
      // "first 100 customers free" code was redeemable forever, and validate()'s cap check
      // read a counter this path never moved. The synthetic id keys the same per-payment
      // idempotency marker the webhook pair uses; `credit:` cannot collide with a real
      // provider payment id.
      if (metadata.promotionId) {
        await this.promotions.recordRedemption(metadata.promotionId, `credit:${attemptId}`);
      }
      await this.qualifyReferral(user.id, plan.interval, plan.tier, payable, billingCurrency);
      return { checkoutUrl: params.successUrl, fullyCoveredByCredit: true };
    }

    // Carried through to the webhook so the invoice reads the same as the hosted
    // page the customer actually saw.
    metadata.description = this.planDescription(plan);

    // The credit was DEBITED at step 4, before this call, and consume() commits its own
    // transaction — so nothing downstream can roll it back. Every path that returns credit
    // (onPaymentDeclined, onCheckoutExpired) is driven by a webhook for a session that
    // EXISTS. If the session is never created, no event can ever arrive and the debit is
    // permanent: the customer's referral credit is simply gone, and clicking again spends
    // whatever is left, because each attempt mints a fresh attemptId.
    //
    // That is not hypothetical. createHostedPayment throws whenever STRIPE_SECRET_KEY is
    // unset — today's state, since the account is not live yet — and converts every
    // transient Stripe failure into the same BadRequestException.
    //
    // subscriptions.service.ts already does exactly this for a declined renewal ("Give the
    // credit back — it was not actually spent"). Checkout is the sibling path that did not.
    let session: Awaited<ReturnType<typeof this.provider.createHostedPayment>>;
    try {
      session = await this.provider.createHostedPayment({
      userId: user.id,
      email: user.email,
      amountMinor: amountDue,
      currency: billingCurrency,
      description: metadata.description,
      // Set once the catalogue has been mirrored (admin: POST /admin/commerce/
      // stripe-catalog/sync), so the charge belongs to a real product in the provider's
      // dashboard instead of a one-off line. Null before the first sync, which is the
      // old behaviour and still correct.
      productId: plan.providerProductId ?? undefined,
      successUrl: params.successUrl,
      cancelUrl: params.cancelUrl,
      // Recurring plans need a stored card so we can charge renewals ourselves.
      storeInstrument: isRecurring(plan.interval),
      metadata,
      });
    } catch (e) {
      // Give the credit back — it was not actually spent. Keyed on the SAME attemptId as
      // the debit, so the ledger reads as a matched consume/reverse pair, and so a webhook
      // that somehow arrives later for this attempt cannot return it a second time.
      if (applied > 0) {
        await this.credits
          .grant({
            userId: user.id,
            amountMinor: applied,
            currency: billingCurrency,
            reason: 'MANUAL_ADJUSTMENT',
            description: 'Credit returned — checkout could not be started',
            sourceType: 'CheckoutCreditReturn',
            sourceId: attemptId,
          })
          .catch((err) =>
            // The customer is about to see an error either way; losing their credit on top
            // of it is the part that must not pass silently.
            this.logger.error(
              `Checkout failed for ${user.id} and the ${applied} ${billingCurrency} credit ` +
                `return ALSO failed (attempt ${attemptId}): ${(err as Error).message}`,
            ),
          );
      }
      throw e;
    }

    return { checkoutUrl: session.redirectUrl };
  }

  /** The one wording used on the hosted page, the receipt and the invoice list. */
  private planDescription(plan: { displayName: string; interval: PriceInterval }): string {
    const cadence = plan.interval === 'ONE_TIME' ? 'one-time' : plan.interval.toLowerCase();
    return `Wasiati ${plan.displayName} (${cadence})`;
  }


  /**
   * Grants entitlement after a successful payment. Idempotent: re-running for the
   * same user+tier updates rather than duplicating.
   */
  private async fulfil(params: {
    userId: string;
    tier: SubscriptionTier;
    interval: PriceInterval;
    planId: string;
    paymentInstrumentId?: string;
  }) {
    if (params.interval === 'ONE_TIME') {
      // Record the one-time purchase as a NON-RENEWING entitlement so EntitlementsService
      // resolves the buyer's tier (BASIC) — which is what gates will creation and locks
      // the will. Without this the buyer had no entitlement, so the wills.create clamp
      // was a no-op and they could stamp a STANDARD (unlocked) will they never paid for.
      // currentPeriodEnd stays null, so the renewal cron (which requires
      // currentPeriodEnd <= now) never picks it up to charge again. Idempotent across the
      // approved+captured webhook pair.
      const existing = await this.prisma.subscription.findFirst({
        where: { userId: params.userId, tier: params.tier, interval: 'ONE_TIME' },
      });
      if (!existing) {
        await this.prisma.subscription.create({
          data: {
            userId: params.userId,
            tier: params.tier,
            interval: 'ONE_TIME',
            status: 'ACTIVE',
            currentPeriodEnd: null,
            ...(params.paymentInstrumentId ? { paymentInstrumentId: params.paymentInstrumentId } : {}),
          },
        });
      } else if (existing.status !== 'ACTIVE') {
        await this.prisma.subscription.update({ where: { id: existing.id }, data: { status: 'ACTIVE' } });
      }
      this.logger.log(`One-time ${params.tier} purchase fulfilled for ${params.userId}.`);
      return;
    }

    const periodEnd = this.nextPeriodEnd(new Date(), params.interval);
    // Match only RECURRING rows. A ONE_TIME row of the same tier is a lifetime
    // purchase ("yours for life"): updating IT here would stamp an interval and a
    // currentPeriodEnd onto it — silently converting a paid-in-full entitlement
    // into a renewing, dunnable, cancellable subscription. It must never renew and
    // must never be matched by a recurring fulfilment.
    const existing = await this.prisma.subscription.findFirst({
      where: {
        userId: params.userId,
        tier: params.tier,
        interval: { in: PaymentsService.RECURRING_INTERVALS },
      },
    });

    let fulfilledId: string;
    if (existing) {
      await this.prisma.subscription.update({
        where: { id: existing.id },
        data: {
          status: 'ACTIVE',
          interval: params.interval,
          currentPeriodEnd: periodEnd,
          cancelAtPeriodEnd: false,
          canceledAt: null,
          failedPaymentCount: 0,
          lastPaymentAt: new Date(),
          ...(params.paymentInstrumentId ? { paymentInstrumentId: params.paymentInstrumentId } : {}),
        },
      });
      fulfilledId = existing.id;
    } else {
      const created = await this.prisma.subscription.create({
        data: {
          userId: params.userId,
          tier: params.tier,
          status: 'ACTIVE',
          interval: params.interval,
          currentPeriodEnd: periodEnd,
          lastPaymentAt: new Date(),
          paymentInstrumentId: params.paymentInstrumentId,
          providerPriceId: params.planId,
        },
      });
      fulfilledId = created.id;
    }

    // INVARIANT: at most ONE live recurring subscription per user. Paying for a
    // new recurring plan SUPERSEDES any other live one — without this, buying a
    // second tier left BOTH rows active, the renewal cron charged them BOTH
    // forever, and the older row was invisible to billingOverview (newest-first)
    // so it could not even be cancelled. Superseding rather than refusing keeps
    // the upgrade path open; the new plan starts a fresh full period immediately,
    // so the customer is never uncovered. ONE_TIME rows are lifetime entitlements
    // and are deliberately NOT superseded. Idempotent: a replayed webhook finds
    // nothing left to supersede.
    const superseded = await this.prisma.subscription.updateMany({
      where: {
        userId: params.userId,
        id: { not: fulfilledId },
        status: { in: ['ACTIVE', 'PAST_DUE'] },
        interval: { in: PaymentsService.RECURRING_INTERVALS },
      },
      data: { status: 'CANCELED', canceledAt: new Date(), cancelAtPeriodEnd: false },
    });
    if (superseded.count > 0) {
      this.logger.log(
        `${params.userId} switched to ${params.tier} (${params.interval}); superseded ${superseded.count} previous recurring subscription(s).`,
      );
    }
  }

  /**
   * The one subscription that can still take the user's money — fulfil enforces
   * that at most one exists. ONE_TIME rows are excluded: they never renew, so
   * "cancel", "resume" and "change card" are meaningless for them.
   */
  private liveRecurringSubscription(userId: string) {
    return this.prisma.subscription.findFirst({
      where: {
        userId,
        status: { in: ['ACTIVE', 'PAST_DUE'] },
        interval: { in: PaymentsService.RECURRING_INTERVALS },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Adds one billing period. Used by both first payment and renewals. */
  nextPeriodEnd(from: Date, interval: PriceInterval): Date {
    const d = new Date(from);
    if (interval === 'YEAR') d.setUTCFullYear(d.getUTCFullYear() + 1);
    else d.setUTCMonth(d.getUTCMonth() + 1);
    return d;
  }

  // --- webhook -------------------------------------------------------------

  async handleWebhook(rawBody: Buffer, signature: string) {
    const event = this.provider.parseWebhook(rawBody, signature); // throws on bad signature

    // Idempotency, race-safe: CLAIM the event by inserting its id FIRST. The PK
    // unique constraint means two concurrent deliveries of the same event can't both
    // win — the loser gets P2002 and no-ops. (A find-then-process-then-insert order
    // let both pass the check and double-fire the referral/promo ledgers.)
    try {
      await this.prisma.processedPaymentEvent.create({ data: { id: event.id, type: event.type } });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        return { received: true, duplicate: true };
      }
      throw e;
    }

    try {
      switch (event.type) {
        case 'payment_approved':
        case 'payment_captured':
          await this.onPaymentApproved(event);
          break;
        case 'payment_declined':
          await this.onPaymentDeclined(event.metadata);
          break;
        case 'checkout_expired':
          await this.onCheckoutExpired(event.metadata);
          break;
        case 'payment_refunded':
          await this.onPaymentRefunded(event.metadata, event.providerPaymentId);
          break;
        case 'instrument_stored':
          await this.onInstrumentStored(event.metadata, event.paymentInstrumentId);
          break;
        default:
          this.logger.log(`Unhandled provider event: ${event.type}`);
          break;
      }
    } catch (e) {
      // Processing failed — release the claim so the provider's retry can reprocess,
      // rather than the event being permanently marked done.
      await this.prisma.processedPaymentEvent.delete({ where: { id: event.id } }).catch(() => undefined);
      this.logger.error(`Webhook ${event.type} (${event.id}) failed: ${(e as Error).message}`);
      throw e; // let the provider retry
    }
    return { received: true };
  }

  private async onPaymentApproved(event: PaymentEvent) {
    const metadata = event.metadata;
    const { userId, tier, interval } = metadata;
    if (!userId || !tier || !interval) return;

    await this.fulfil({
      userId,
      tier: tier as SubscriptionTier,
      interval: interval as PriceInterval,
      planId: metadata.planId,
      paymentInstrumentId: event.paymentInstrumentId,
    });

    // The receipt for the money just taken. Keyed on the PROVIDER PAYMENT id, not
    // the event id: approved and captured are two events for one payment, and the
    // customer is owed one invoice, not two.
    const creditApplied = Number(metadata.creditAppliedMinor ?? 0);
    if (event.providerPaymentId) {
      await this.invoices.record({
        userId,
        idempotencyKey: event.providerPaymentId,
        description: metadata.description ?? `Wasiati ${tier}`,
        // The event carries what the CARD was charged; the invoice total is that
        // plus whatever account credit settled, so the receipt shows the real price.
        amountMinor: (event.amountMinor ?? Number(metadata.basisMinor ?? 0)) + creditApplied,
        currency: event.currency ?? metadata.basisCurrency ?? '',
        creditAppliedMinor: creditApplied,
        tier: tier as SubscriptionTier,
        interval: interval as PriceInterval,
        providerPaymentId: event.providerPaymentId,
      });
    }

    // `payment_approved` and `payment_captured` are distinct events (distinct event ids,
    // so each clears the per-event idempotency) but share one providerPaymentId. Passing
    // it lets the redemption counter increment exactly once per payment, not twice.
    if (metadata.promotionId) await this.promotions.recordRedemption(metadata.promotionId, event.providerPaymentId);

    await this.qualifyReferral(
      userId,
      interval as PriceInterval,
      tier as SubscriptionTier,
      Number(metadata.basisMinor ?? 0),
      metadata.basisCurrency ?? '',
    );
  }

  /**
   * The "change card" flow completing: swap the stored instrument on the user's
   * subscription so the NEXT renewal charges the new card.
   *
   * Only the subscription's instrument moves — nothing is charged here, and a
   * card stored while no subscription exists is simply nothing to attach.
   */
  private async onInstrumentStored(metadata: Record<string, string>, paymentInstrumentId?: string) {
    const userId = metadata.userId;
    if (!userId || !paymentInstrumentId) return;

    // A stored card exists to pay RENEWALS: attach it to the live recurring
    // subscription, never to a ONE_TIME row that will never charge anything.
    const sub = await this.liveRecurringSubscription(userId);
    if (!sub) {
      this.logger.warn(`Card stored for ${userId} but they have no live subscription to attach it to.`);
      return;
    }

    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: {
        paymentInstrumentId,
        // A new card is the customer fixing a failed payment. Clear the dunning
        // counter so a past-due subscription gets a full set of retries on it
        // rather than being cancelled by strikes the old card earned.
        failedPaymentCount: 0,
      },
    });
    this.logger.log(`Payment method updated for ${userId} (subscription ${sub.id}).`);
  }

  /**
   * Referral qualification: annual subscription or one-time purchase. The referrer
   * earns 2.5% of `basisMinor`. A referral failure must never break the purchase.
   */
  private async qualifyReferral(
    userId: string,
    interval: PriceInterval,
    tier: SubscriptionTier,
    basisMinor: number,
    currency: string,
  ): Promise<void> {
    try {
      await this.referrals.handleQualifyingPurchase({ userId, interval, tier, basisMinor, currency });
    } catch (e) {
      this.logger.error(`Referral handling failed for ${userId}: ${(e as Error).message}`);
    }
  }

  /**
   * Returns the account credit a checkout attempt consumed — EXACTLY ONCE per
   * attempt. Two independent layers make "once" hold:
   *   1. handleWebhook's ProcessedPaymentEvent claim: a REPLAYED event id no-ops
   *      before it ever reaches here.
   *   2. The credit ledger's (sourceType, sourceId, userId) unique key, keyed on
   *      the attemptId: a decline followed by the SAME session expiring is two
   *      DISTINCT event ids — layer 1 passes both — but one attempt, so the
   *      second grant lands on the same ledger key and no-ops.
   */
  private async returnCheckoutCredit(metadata: Record<string, string>, cause: string) {
    const applied = Number(metadata.creditAppliedMinor ?? 0);
    if (!metadata.userId || !(applied > 0) || !metadata.creditCurrency) return;
    const { granted } = await this.credits.grant({
      userId: metadata.userId,
      amountMinor: applied,
      currency: metadata.creditCurrency,
      reason: CreditReason.MANUAL_ADJUSTMENT,
      description: `Credit returned after ${cause}`,
      sourceType: 'CheckoutCreditReturn',
      // One return per checkout ATTEMPT. Sessions created before attemptId was
      // stamped into metadata fall back to the old per-plan key.
      sourceId: metadata.attemptId ?? metadata.planId ?? metadata.userId,
    });
    if (granted) {
      this.logger.log(`Returned ${applied} ${metadata.creditCurrency} credit to ${metadata.userId} after ${cause}.`);
    }
  }

  /** A declined payment must give the customer their credit back. */
  private async onPaymentDeclined(metadata: Record<string, string>) {
    // A declined RENEWAL is not a checkout. SubscriptionsService.renew sees the
    // decline synchronously and has ALREADY returned that credit ('RenewalFailed');
    // returning it here too paid the customer twice for one decline.
    if (metadata.subscriptionId) return;
    await this.returnCheckoutCredit(metadata, 'a declined payment');
  }

  /**
   * An abandoned checkout must give the customer their credit back. The credit
   * was consumed when the session was CREATED (the hosted page needs a final
   * amount); if the customer closes the tab, the session expiring is the only
   * signal the money will never arrive — without this, opening checkout and
   * walking away silently cost them real balance.
   */
  private async onCheckoutExpired(metadata: Record<string, string>) {
    await this.returnCheckoutCredit(metadata, 'an expired checkout session');
  }

  private async onPaymentRefunded(metadata: Record<string, string>, providerPaymentId?: string) {
    if (!metadata.userId) return;
    // A refunded qualifying purchase invalidates its referral reward.
    await this.referrals.rejectForRefund(metadata.userId, 'Qualifying purchase refunded');

    // The receipt must stop claiming the customer paid.
    if (providerPaymentId) await this.invoices.markRefunded(providerPaymentId);

    // Cancel the subscription the refunded payment PAID FOR — the metadata names
    // it. An unscoped lookup could grab any row, e.g. cancel a lifetime ONE_TIME
    // entitlement because a later recurring payment was refunded.
    const sub = await this.prisma.subscription.findFirst({
      where: {
        userId: metadata.userId,
        ...(metadata.tier ? { tier: metadata.tier as SubscriptionTier } : {}),
        ...(metadata.interval ? { interval: metadata.interval as PriceInterval } : {}),
      },
      orderBy: { createdAt: 'desc' },
    });
    if (sub) {
      await this.prisma.subscription.update({
        where: { id: sub.id },
        data: { status: 'CANCELED', canceledAt: new Date() },
      });
    }
  }

  // --- self-serve billing (we deliberately use no hosted portal — we ARE the portal) ---

  async mySubscription(userId: string) {
    // The subscription that can still bill them, in preference to whatever row
    // happens to be newest — a canceled row must never mask the one taking money.
    const sub =
      (await this.liveRecurringSubscription(userId)) ??
      (await this.prisma.subscription.findFirst({
        where: { userId },
        orderBy: { createdAt: 'desc' },
      }));
    if (!sub) return null;
    return {
      tier: sub.tier,
      status: sub.status,
      interval: sub.interval,
      currentPeriodEnd: sub.currentPeriodEnd,
      cancelAtPeriodEnd: sub.cancelAtPeriodEnd,
      hasPaymentMethod: !!sub.paymentInstrumentId,
    };
  }

  /**
   * Everything the "Manage billing" page shows, in one round trip: the plan and
   * what it renews at, the card, and the receipts.
   *
   * Degrades honestly rather than pretending. With no provider keys, `card` is
   * null and `canChangeCard` is false — the page then states that card management
   * is unavailable on this environment instead of offering a button that can only
   * fail. Everything else on the page is OURS (we run the billing cycle), so it
   * stays fully truthful with no provider at all.
   */
  async billingOverview(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { region: true, email: true },
    });
    if (!user) throw new NotFoundException('User not found.');

    // Prefer the subscription that can still bill them (there is at most one) —
    // the "Manage billing" page is above all the place a paying plan must be
    // visible, and therefore cancellable. Fall back to the newest row so a fully
    // cancelled or lifetime-only account still sees its state.
    const sub =
      (await this.liveRecurringSubscription(userId)) ??
      (await this.prisma.subscription.findFirst({
        where: { userId },
        orderBy: { createdAt: 'desc' },
      }));

    // The live catalog price for what they hold — priced in the ACCOUNT region, the
    // same rule as everywhere else, so the renewal line cannot quote another
    // market's number.
    const plan =
      sub && sub.interval
        ? await this.prisma.pricingPlan.findFirst({
            where: { tier: sub.tier, interval: sub.interval, region: user.region, active: true },
          })
        : null;

    const providerConfigured = this.provider.isConfigured();
    const card =
      sub?.paymentInstrumentId && providerConfigured
        ? await this.provider.describeInstrument(sub.paymentInstrumentId)
        : null;

    return {
      subscription: sub
        ? {
            tier: sub.tier,
            status: sub.status,
            interval: sub.interval,
            currentPeriodEnd: sub.currentPeriodEnd,
            cancelAtPeriodEnd: sub.cancelAtPeriodEnd,
          }
        : null,
      plan: plan
        ? {
            displayName: plan.displayName,
            unitAmount: plan.unitAmount,
            currency: plan.currency,
            interval: plan.interval,
          }
        : null,
      // True when a card is stored, whether or not we can currently describe it.
      hasPaymentMethod: !!sub?.paymentInstrumentId,
      card,
      /** False without provider keys: the app hides/disables "Change card". */
      canChangeCard: providerConfigured && !!sub,
      invoices: await this.invoices.listForUser(userId),
    };
  }

  /**
   * Starts the hosted "change card" flow. Nothing is charged and nothing is
   * swapped here — the stored instrument only moves when the provider confirms the
   * card was tokenised (see onInstrumentStored), so an abandoned flow leaves the
   * working card exactly where it was.
   */
  async changePaymentMethod(userId: string, successUrl: string, cancelUrl: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found.');

    // Same open-redirect constraint as checkout — these come back to the browser.
    this.assertReturnUrl(successUrl);
    this.assertReturnUrl(cancelUrl);

    const sub = await this.liveRecurringSubscription(userId);
    if (!sub) throw new BadRequestException('There is no active subscription to change the card for.');

    const session = await this.provider.createInstrumentSetup({
      userId: user.id,
      email: user.email,
      existingInstrumentId: sub.paymentInstrumentId ?? undefined,
      // The currency renewals will actually be charged in — from the ACCOUNT
      // region, the same rule as everywhere else — so the hosted page offers the
      // right payment methods (mada in KSA rather than card-only).
      currency: resolveBillingCurrency(user.region),
      successUrl,
      cancelUrl,
      metadata: { userId: user.id, subscriptionId: sub.id },
    });
    return { setupUrl: session.redirectUrl };
  }

  /**
   * Cancels at period end — the customer keeps what they paid for. We schedule it
   * ourselves; there is no provider subscription to update.
   */
  async cancelSubscription(userId: string) {
    // Target the subscription that BILLS — never a ONE_TIME row. A lifetime
    // purchase never charges again, and letting it absorb the cancel would leave
    // the actually-billing plan running with no way out.
    const sub = await this.liveRecurringSubscription(userId);
    if (!sub) throw new BadRequestException('No active subscription to cancel.');

    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: { cancelAtPeriodEnd: true, canceledAt: new Date() },
    });

    // A burial plan is PREPAYMENT, not credit: it can never hold the subscription
    // hostage. Cancelling stops future contributions and returns what was paid.
    const refund = await this.cancelBurialPlanForUser(userId, 'Subscription cancelled');

    return { scheduledCancellation: true, effectiveAt: sub.currentPeriodEnd, burialRefund: refund };
  }

  async resume(userId: string) {
    // Only a LIVE recurring subscription can be resumed. Without the status
    // filter this could flip flags on an already-superseded or finalised row and
    // quietly resurrect a plan the user already replaced — double-billing again.
    const sub = await this.prisma.subscription.findFirst({
      where: {
        userId,
        cancelAtPeriodEnd: true,
        status: { in: ['ACTIVE', 'PAST_DUE'] },
        interval: { in: PaymentsService.RECURRING_INTERVALS },
      },
      orderBy: { createdAt: 'desc' },
    });
    if (!sub) throw new NotFoundException('Nothing to resume.');
    await this.prisma.subscription.update({
      where: { id: sub.id },
      data: { cancelAtPeriodEnd: false, canceledAt: null },
    });
    return { cancelAtPeriodEnd: false };
  }

  // --- burial prepayment (escrow, NOT installments) --------------------------
  //
  // The customer prepays a grave reserved today at today's price. The money is
  // theirs, held in trust: it is refundable on demand, it never blocks cancelling
  // the subscription, and the plan never self-completes. If they die part-funded,
  // the reservation stands and the family settles the balance — a plan that paid
  // out in full would be preneed insurance. See docs/DECISIONS.md §6.

  /** The user's plan still receiving contributions, if any. */
  async activeBurialPlan(userId: string) {
    return this.prisma.burialPrepaymentPlan.findFirst({
      where: { userId, status: 'ACTIVE' },
      orderBy: { createdAt: 'desc' },
    });
  }

  async burialPlanStatus(userId: string) {
    const plans = await this.prisma.burialPrepaymentPlan.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
    const active = plans.find((p) => p.status === 'ACTIVE') ?? null;
    return {
      plans,
      active,
      // Contributions are the customer's money — always refundable, never forfeit.
      refundableMinor: active?.amountPaid ?? 0,
      currency: active?.currency ?? null,
    };
  }

  /**
   * Stops contributions and records what must be returned. The refund itself is
   * settled out-of-band (we hold no per-contribution payment ids), so this leaves
   * an explicit `refundDueMinor` for the admin refund queue rather than pretending
   * the money has already moved.
   */
  async cancelBurialPlanForUser(userId: string, reason: string) {
    const plan = await this.activeBurialPlan(userId);
    if (!plan) return null;

    const updated = await this.prisma.burialPrepaymentPlan.update({
      where: { id: plan.id },
      data: { status: 'CANCELLED', cancelledAt: new Date(), refundDueMinor: plan.amountPaid },
    });
    if (plan.amountPaid > 0) {
      this.logger.warn(
        `Burial plan ${plan.id} cancelled (${reason}); ${plan.amountPaid} ${plan.currency} is refundable to user ${userId}.`,
      );
    }
    return { planId: updated.id, refundDueMinor: updated.refundDueMinor, currency: updated.currency };
  }

  /**
   * The refund queue: cancelled plans whose contributions have not been returned.
   * Cancelling records the debt; a human moves the money and calls settleRefund.
   * Without this the money we owe is invisible.
   */
  async pendingBurialRefunds() {
    const plans = await this.prisma.burialPrepaymentPlan.findMany({
      where: { status: 'CANCELLED', refundDueMinor: { gt: 0 } },
      orderBy: { cancelledAt: 'asc' },
      include: { user: { select: { id: true, email: true, region: true } } },
    });
    const totals = plans.reduce<Record<string, number>>((acc, p) => {
      acc[p.currency] = (acc[p.currency] ?? 0) + (p.refundDueMinor ?? 0);
      return acc;
    }, {});
    return { count: plans.length, totalsByCurrency: totals, plans };
  }

  /** Marks a refund as paid out. Idempotent: settling twice is a no-op. */
  async settleBurialRefund(planId: string) {
    const plan = await this.prisma.burialPrepaymentPlan.findUnique({ where: { id: planId } });
    if (!plan) throw new BadRequestException('Burial plan not found.');
    if (plan.status !== 'CANCELLED') {
      throw new BadRequestException('Only a cancelled plan can have a refund settled.');
    }
    if (!plan.refundDueMinor) return { settled: false, alreadySettled: true };

    const settled = await this.prisma.burialPrepaymentPlan.update({
      where: { id: planId },
      data: { refundDueMinor: 0 },
    });
    this.logger.log(`Burial refund settled for plan ${planId}: ${plan.refundDueMinor} ${plan.currency}.`);
    return { settled: true, planId: settled.id, amountMinor: plan.refundDueMinor, currency: plan.currency };
  }

  async createBurialPlan(
    userId: string,
    data: { currency: string; totalAmount: number; amountPaid?: number; maturesAt?: string },
  ) {
    return this.prisma.burialPrepaymentPlan.create({
      data: {
        userId,
        currency: data.currency.toUpperCase(),
        totalAmount: data.totalAmount,
        amountPaid: data.amountPaid ?? 0,
        maturesAt: data.maturesAt ? new Date(data.maturesAt) : null,
      },
    });
  }

  /** Record a contribution toward the grave; the plan is FULLY_FUNDED once covered. */
  async recordBurialContribution(planId: string, amount: number) {
    const plan = await this.prisma.burialPrepaymentPlan.findUnique({ where: { id: planId } });
    if (!plan) throw new BadRequestException('Burial plan not found.');
    if (plan.status === 'CANCELLED') throw new BadRequestException('That burial plan was cancelled.');

    const amountPaid = plan.amountPaid + amount;
    const fullyFunded = amountPaid >= plan.totalAmount;
    return this.prisma.burialPrepaymentPlan.update({
      where: { id: planId },
      data: { amountPaid, status: fullyFunded ? 'FULLY_FUNDED' : plan.status },
    });
  }
}
