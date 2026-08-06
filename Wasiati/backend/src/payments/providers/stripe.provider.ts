import { BadRequestException, Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
// stripe's CJS build uses `export =`; this tsconfig has no esModuleInterop, so a
// default import would be `undefined` at runtime. import-equals is the safe form.
import Stripe = require('stripe');
import {
  CatalogEntry,
  CatalogSyncResult,
  ChargeResult,
  HostedPaymentRequest,
  HostedPaymentSession,
  InstrumentSetupRequest,
  InstrumentSetupSession,
  PaymentEvent,
  PaymentProviderPort,
  RecurringChargeRequest,
  StoredInstrument,
} from '../payment-provider.interface';

/**
 * Stripe adapter — Stripe as a dumb PSP, nothing more.
 *
 * We deliberately do NOT use Stripe Billing, Subscriptions, Coupons or the
 * Customer Portal. The billing cycle, promotions and account credit are OUR code
 * (SubscriptionsService, PromotionsService, CreditsService), so the port stays
 * portable and a future PSP swap touches only this file. What we do use:
 *  · Checkout Sessions (mode 'payment') → the hosted page for one-off purchases
 *    and the FIRST payment of a subscription.
 *  · When storing a card, the session creates a Customer and attaches the
 *    PaymentMethod for off-session reuse. The port carries ONE instrument string,
 *    so the pair is encoded as `cus_xxx|pm_xxx` in `paymentInstrumentId`.
 *  · PaymentIntents (off_session, confirm) → merchant-initiated renewals.
 *  · Refunds, and signature-verified webhooks.
 */
@Injectable()
export class StripeProvider implements PaymentProviderPort {
  readonly name = 'stripe';
  private readonly logger = new Logger(StripeProvider.name);

  /** Lazy — constructed on first API call so the app boots without keys. */
  private sdk?: Stripe;
  /** Signature verification is pure HMAC (no network), so it must work with only
   *  the webhook secret configured — mirror of the old provider's behavior. */
  private verifier?: Stripe;

  constructor(private config: ConfigService) {}

  /** No secret key = this environment cannot move money. Callers use this to
   *  degrade honestly instead of offering actions that can only fail. */
  isConfigured(): boolean {
    return !!this.config.get<string>('STRIPE_SECRET_KEY');
  }

  /** Throws (not crashes) when unconfigured, so the local demo still boots and
   *  payment endpoints fail clearly — same degradation as before the swap. */
  private client(): Stripe {
    if (this.sdk) return this.sdk;
    const key = this.config.get<string>('STRIPE_SECRET_KEY');
    if (!key) throw new BadRequestException('Payments are not configured on this environment.');
    this.sdk = new Stripe(key);
    return this.sdk;
  }

  /** API-key-independent instance used only for webhook signature verification. */
  private webhookVerifier(): Stripe {
    if (this.verifier) return this.verifier;
    this.verifier = new Stripe(this.config.get<string>('STRIPE_SECRET_KEY') ?? 'sk_webhook_verify_only');
    return this.verifier;
  }

  /** Composes the single instrument string the port carries. */
  private static composeInstrument(customer?: string | null, paymentMethod?: string | null): string | undefined {
    return customer && paymentMethod ? `${customer}|${paymentMethod}` : undefined;
  }

  /** Splits the port's `cus_xxx|pm_xxx` back into the pair Stripe needs. */
  private static splitInstrument(instrumentId?: string): { customer?: string; paymentMethod?: string } {
    const [customer, paymentMethod] = (instrumentId ?? '').split('|');
    return { customer: customer || undefined, paymentMethod: paymentMethod || undefined };
  }

  /** Stripe expands some webhook fields into objects; we only ever want the id. */
  private static idOf(value: string | { id: string } | null | undefined): string | undefined {
    if (!value) return undefined;
    return typeof value === 'string' ? value : value.id;
  }

  /**
   * Mirrors one catalogue row into Stripe's Products/Prices, one way.
   *
   * Two Stripe facts shape this:
   *
   *  1. **A Price is immutable.** Changing the list price means creating a new Price
   *     and deactivating the old one — it cannot be edited. Old Prices are left in
   *     place, deactivated, because historical payments reference them.
   *  2. **Prices here are one-off, not `recurring`.** Wasiati runs its own billing
   *     cycle and charges each renewal as a separate PaymentIntent, so declaring a
   *     Stripe recurring price would describe a subscription Stripe does not run and
   *     is not what any charge actually uses.
   *
   * The Price exists so the dashboard's catalogue reads as a real price list. What a
   * customer pays still comes from `price_data.unit_amount` at checkout, because it is
   * computed per purchase.
   */
  async syncCatalogEntry(entry: CatalogEntry): Promise<CatalogSyncResult> {
    const stripe = this.client();
    const name = `Wasiati ${entry.displayName} — ${entry.region}`;
    const metadata = { tier: entry.tier, region: entry.region, interval: entry.interval, source: 'wasiati-catalog' };

    // One Product per (tier, region); its Prices carry the cadences.
    let productId = entry.existingProductId ?? undefined;
    if (productId) {
      try {
        await stripe.products.update(productId, {
          name,
          active: entry.active,
          ...(entry.description ? { description: entry.description } : {}),
          metadata,
        });
      } catch {
        // Deleted in the dashboard, or belongs to another account (a key was rotated
        // between environments). Fall through and make a fresh one rather than fail
        // the whole sync on one row.
        productId = undefined;
      }
    }
    if (!productId) {
      const created = await stripe.products.create({
        name,
        active: entry.active,
        ...(entry.description ? { description: entry.description } : {}),
        metadata,
      });
      productId = created.id;
    }

    // Reuse the existing Price only when the amount and currency still match.
    let priceId = entry.existingPriceId ?? undefined;
    let priceReplaced = false;
    if (priceId) {
      try {
        const existing = await stripe.prices.retrieve(priceId);
        const same =
          existing.unit_amount === entry.unitAmount &&
          existing.currency === entry.currency.toLowerCase() &&
          existing.product === productId;
        if (!same) {
          if (existing.active) await stripe.prices.update(priceId, { active: false });
          priceId = undefined;
          priceReplaced = true;
        } else if (existing.active !== entry.active) {
          await stripe.prices.update(priceId, { active: entry.active });
        }
      } catch {
        priceId = undefined;
      }
    }
    if (!priceId) {
      const price = await stripe.prices.create({
        product: productId,
        currency: entry.currency.toLowerCase(),
        unit_amount: entry.unitAmount,
        active: entry.active,
        nickname: `${entry.displayName} · ${entry.interval}`,
        metadata,
      });
      priceId = price.id;
    }

    return { productId, priceId, priceReplaced };
  }

  async createHostedPayment(req: HostedPaymentRequest): Promise<HostedPaymentSession> {
    let session: Stripe.Checkout.Session;
    try {
      session = await this.client().checkout.sessions.create({
        mode: 'payment',
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: req.currency.toLowerCase(),
              // The amount is always computed by us — list price after promo, referral
              // and credit — so it can never be a stored Stripe Price, which is a fixed
              // immutable amount. Naming the `product` is what gives the charge a real
              // catalogue identity, so the dashboard reports by product instead of by a
              // throwaway description, and the discount still lands.
              unit_amount: req.amountMinor,
              ...(req.productId ? { product: req.productId } : { product_data: { name: req.description } }),
            },
          },
        ],
        success_url: req.successUrl,
        cancel_url: req.cancelUrl,
        customer_email: req.email,
        // Any account credit applied to this attempt is HELD until the session
        // completes or expires (checkout.session.expired returns it). Stripe's
        // default expiry is 24h; an hour is plenty to pay, and it caps how long
        // an abandoned tab can sit on a customer's balance. (Stripe minimum: 30m.)
        expires_at: Math.floor(Date.now() / 1000) + 60 * 60,
        // Echoed back on checkout.session.completed for reconciliation.
        metadata: req.metadata,
        // Also stamped on the PaymentIntent so payment_intent.succeeded /
        // payment_failed events reconcile too (the session id is not on those).
        payment_intent_data: {
          metadata: req.metadata,
          // Tokenise the card for merchant-initiated renewals. A Customer is
          // required to reuse a PaymentMethod off-session, hence customer_creation.
          ...(req.storeInstrument ? { setup_future_usage: 'off_session' as const } : {}),
        },
        ...(req.storeInstrument ? { customer_creation: 'always' as const } : {}),
      });
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      this.logger.error(`Stripe checkout.sessions.create failed: ${(e as Error).message}`);
      throw new BadRequestException('Payment provider error.');
    }

    if (!session.url) throw new BadRequestException('Payment provider did not return a redirect link.');
    return { redirectUrl: session.url, sessionId: session.id };
  }

  /**
   * "Change card": a Checkout Session in `mode: 'setup'`.
   *
   * That is the hosted SetupIntent flow — Stripe collects and tokenises the card
   * on its own page and confirms a SetupIntent, so a PAN never touches us and 3DS
   * is handled while the customer is present (which is exactly what makes the
   * later off-session renewal charges work).
   *
   * When the customer already has an instrument we pass its `cus_...` so the new
   * card attaches to the SAME Stripe Customer; otherwise Checkout creates one in
   * setup mode. The stored instrument is only swapped when the webhook confirms
   * the SetupIntent succeeded — not here.
   */
  async createInstrumentSetup(req: InstrumentSetupRequest): Promise<InstrumentSetupSession> {
    const { customer } = StripeProvider.splitInstrument(req.existingInstrumentId);
    let session: Stripe.Checkout.Session;
    try {
      session = await this.client().checkout.sessions.create({
        mode: 'setup',
        // Nothing is charged here, but the currency decides which payment methods
        // the hosted page offers — so it must be the one we will actually bill in
        // (mada for a Saudi customer), not a hardcoded default.
        currency: req.currency.toLowerCase(),
        success_url: req.successUrl,
        cancel_url: req.cancelUrl,
        ...(customer ? { customer } : { customer_email: req.email }),
        metadata: req.metadata,
        // Stamped on the SetupIntent too: setup_intent.succeeded is the event that
        // carries the payment_method, and the session id is not on it.
        setup_intent_data: { metadata: req.metadata },
      });
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      this.logger.error(`Stripe setup session create failed: ${(e as Error).message}`);
      throw new BadRequestException('Payment provider error.');
    }

    if (!session.url) throw new BadRequestException('Payment provider did not return a redirect link.');
    return { redirectUrl: session.url, sessionId: session.id };
  }

  /**
   * Brand/last4 for the billing page. Never throws: an unconfigured or unreachable
   * provider yields null and the page says "card on file" instead of claiming a
   * card we cannot actually see.
   */
  async describeInstrument(paymentInstrumentId: string): Promise<StoredInstrument | null> {
    const { paymentMethod } = StripeProvider.splitInstrument(paymentInstrumentId);
    if (!paymentMethod) return null;
    try {
      const pm = await this.client().paymentMethods.retrieve(paymentMethod);
      return {
        // `card.brand` is 'visa' | 'mastercard' | 'mada' | …; fall back to the
        // method type so a non-card instrument still names itself.
        brand: pm.card?.brand ?? pm.type ?? null,
        last4: pm.card?.last4 ?? null,
        expMonth: pm.card?.exp_month ?? null,
        expYear: pm.card?.exp_year ?? null,
      };
    } catch (e) {
      this.logger.warn(`Could not describe instrument: ${(e as Error).message}`);
      return null;
    }
  }

  async chargeStoredInstrument(req: RecurringChargeRequest): Promise<ChargeResult> {
    // The port carries one instrument string; Stripe needs the (customer, payment
    // method) pair, stored as `cus_xxx|pm_xxx`.
    const { customer, paymentMethod } = StripeProvider.splitInstrument(req.paymentInstrumentId);
    if (!customer || !paymentMethod) {
      return { approved: false, declineReason: 'Stored payment instrument is not chargeable on this provider.' };
    }

    try {
      const intent = await this.client().paymentIntents.create({
        amount: req.amountMinor,
        currency: req.currency.toLowerCase(),
        customer,
        payment_method: paymentMethod,
        // Merchant-initiated: the customer is not present to complete 3DS.
        off_session: true,
        confirm: true,
        description: req.description,
        metadata: req.metadata,
      });

      return intent.status === 'succeeded'
        ? { approved: true, providerPaymentId: intent.id }
        : {
            approved: false,
            providerPaymentId: intent.id,
            declineReason: intent.last_payment_error?.message ?? intent.status,
          };
    } catch (e) {
      // A decline surfaces as a card_error carrying the failed PaymentIntent.
      const err = e as Stripe.errors.StripeError & { payment_intent?: Stripe.PaymentIntent };
      if (err.type === 'StripeCardError') {
        return {
          approved: false,
          providerPaymentId: err.payment_intent?.id,
          declineReason: err.message,
        };
      }
      return { approved: false, declineReason: (e as Error).message };
    }
  }

  async refund(providerPaymentId: string, amountMinor?: number): Promise<void> {
    try {
      await this.client().refunds.create({
        payment_intent: providerPaymentId,
        ...(amountMinor ? { amount: amountMinor } : {}),
      });
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      this.logger.error(`Stripe refund of ${providerPaymentId} failed: ${(e as Error).message}`);
      throw new BadRequestException('Payment provider error.');
    }
  }

  /**
   * Verifies the `Stripe-Signature` header over the RAW body and normalises the
   * event. Stripe's constructEvent does the timestamped-HMAC check (and replay
   * window) — a bad or missing signature throws.
   */
  parseWebhook(rawBody: Buffer, signature: string): PaymentEvent {
    const secret = this.config.get<string>('STRIPE_WEBHOOK_SECRET');
    if (!secret) throw new BadRequestException('Webhook secret is not configured.');

    let event: Stripe.Event;
    try {
      event = this.webhookVerifier().webhooks.constructEvent(rawBody, signature ?? '', secret);
    } catch {
      throw new UnauthorizedException('Invalid webhook signature.');
    }

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        // Async payment methods complete later (checkout.session.async_payment_succeeded);
        // only a session that has actually been PAID approves anything.
        if (session.payment_status !== 'paid') {
          return { id: event.id, type: 'unknown', metadata: (session.metadata as Record<string, string>) ?? {} };
        }
        return {
          id: event.id,
          type: 'payment_approved',
          providerPaymentId: StripeProvider.idOf(session.payment_intent),
          amountMinor: session.amount_total ?? undefined,
          currency: session.currency?.toUpperCase(),
          // The session payload has no payment_method, so the stored instrument is
          // resolved from the companion payment_intent.succeeded event instead
          // (parseWebhook is synchronous by contract — no retrieve round-trip here).
          paymentInstrumentId: undefined,
          metadata: (session.metadata as Record<string, string>) ?? {},
        };
      }

      case 'payment_intent.succeeded': {
        const intent = event.data.object as Stripe.PaymentIntent;
        return {
          id: event.id,
          type: 'payment_approved',
          providerPaymentId: intent.id,
          amountMinor: intent.amount,
          currency: intent.currency?.toUpperCase(),
          // Present when the payment stored a reusable card (customer + method).
          paymentInstrumentId: StripeProvider.composeInstrument(
            StripeProvider.idOf(intent.customer as string | { id: string } | null),
            StripeProvider.idOf(intent.payment_method as string | { id: string } | null),
          ),
          metadata: (intent.metadata as Record<string, string>) ?? {},
        };
      }

      case 'payment_intent.payment_failed': {
        const intent = event.data.object as Stripe.PaymentIntent;
        // PaymentEvent has no declineReason field (declines matter per-charge, not
        // per-webhook) — log it so a support engineer can see why.
        this.logger.warn(
          `Payment ${intent.id} declined: ${intent.last_payment_error?.message ?? 'no reason given'}`,
        );
        return {
          id: event.id,
          type: 'payment_declined',
          providerPaymentId: intent.id,
          amountMinor: intent.amount,
          currency: intent.currency?.toUpperCase(),
          metadata: (intent.metadata as Record<string, string>) ?? {},
        };
      }

      // The checkout that never happened: the customer opened the hosted page —
      // which CONSUMED their account credit up-front to compute the amount — and
      // walked away. Stripe expires the session and fires this exactly once; the
      // handler returns the credit. Without this case the event fell to `unknown`
      // and the customer's balance was silently gone.
      case 'checkout.session.expired': {
        const session = event.data.object as Stripe.Checkout.Session;
        // Defensive: a paid session does not expire, but never "return" credit
        // for money that was genuinely taken.
        if (session.payment_status === 'paid') {
          return { id: event.id, type: 'unknown', metadata: (session.metadata as Record<string, string>) ?? {} };
        }
        return {
          id: event.id,
          type: 'checkout_expired',
          metadata: (session.metadata as Record<string, string>) ?? {},
        };
      }

      // The "change card" flow completing. This event (not the setup-mode
      // checkout.session.completed) is the one that carries `payment_method`
      // directly on the object, so the new instrument resolves without a
      // retrieve round-trip — parseWebhook is synchronous by contract.
      case 'setup_intent.succeeded': {
        const intent = event.data.object as Stripe.SetupIntent;
        return {
          id: event.id,
          type: 'instrument_stored',
          paymentInstrumentId: StripeProvider.composeInstrument(
            StripeProvider.idOf(intent.customer as string | { id: string } | null),
            StripeProvider.idOf(intent.payment_method as string | { id: string } | null),
          ),
          metadata: (intent.metadata as Record<string, string>) ?? {},
        };
      }

      case 'charge.refunded': {
        const charge = event.data.object as Stripe.Charge;
        return {
          id: event.id,
          type: 'payment_refunded',
          providerPaymentId: StripeProvider.idOf(charge.payment_intent),
          amountMinor: charge.amount_refunded,
          currency: charge.currency?.toUpperCase(),
          metadata: (charge.metadata as Record<string, string>) ?? {},
        };
      }

      default:
        return { id: event.id, type: 'unknown', metadata: {} };
    }
  }
}
