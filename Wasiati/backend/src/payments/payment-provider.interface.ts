import { PriceInterval } from '@prisma/client';

/**
 * The seam between Wasiati and whichever PSP is processing cards.
 *
 * Deliberately narrow: it covers only what a PSP genuinely does — take a payment,
 * store a reusable instrument, charge that instrument later, refund, and verify
 * webhook signatures.
 *
 * It does NOT cover subscriptions, billing portals, coupons or customer credit.
 * We deliberately run our OWN billing cycle in our own code (SubscriptionsService,
 * PromotionsService, CreditsService) rather than adopting a PSP's bundled objects
 * (e.g. Stripe Billing) — those hide the lifecycle behind provider-owned state,
 * which is exactly what makes a PSP hard to port away from.
 */
export interface HostedPaymentRequest {
  userId: string;
  email: string;
  amountMinor: number;
  currency: string;
  /** Human-readable line for the hosted page and the receipt. */
  description: string;
  /**
   * The PSP-side product this charge belongs to, when the catalogue has been mirrored
   * (`PricingPlan.providerProductId`). Absent = the PSP invents a one-off line from
   * [description], which is what it did before the catalogue was synced.
   */
  productId?: string;
  successUrl: string;
  cancelUrl: string;
  /** Ask the PSP to tokenise the card so we can charge renewals later. */
  storeInstrument: boolean;
  /** Echoed back on the webhook so we can reconcile. */
  metadata: Record<string, string>;
}

export interface HostedPaymentSession {
  /** Where to send the customer. */
  redirectUrl: string;
  /** The PSP's id for this attempt, for reconciliation. */
  sessionId: string;
}

export interface RecurringChargeRequest {
  userId: string;
  paymentInstrumentId: string;
  amountMinor: number;
  currency: string;
  description: string;
  metadata: Record<string, string>;
}

/**
 * Asks the PSP to collect and tokenise a card WITHOUT charging it — the
 * "change card" action on the billing page. Card data must never reach us, so
 * this is a hosted page like checkout, not a form we render.
 */
export interface InstrumentSetupRequest {
  userId: string;
  email: string;
  /** Reuse the customer behind an existing instrument, so the new card replaces the
   *  old one on the SAME provider customer instead of orphaning it. */
  existingInstrumentId?: string;
  /**
   * The currency this card will later be CHARGED in. Nothing is charged now, but
   * the currency decides which payment methods the hosted page offers — a Saudi
   * customer must be offered mada, which a USD setup would not surface.
   */
  currency: string;
  successUrl: string;
  cancelUrl: string;
  /** Echoed back on the webhook so we know whose card was stored. */
  metadata: Record<string, string>;
}

export interface InstrumentSetupSession {
  /** Where to send the customer to enter the new card. */
  redirectUrl: string;
  sessionId: string;
}

/** The little we may show about a stored card — never a PAN. */
export interface StoredInstrument {
  /** e.g. 'visa', 'mada'. */
  brand: string | null;
  last4: string | null;
  expMonth?: number | null;
  expYear?: number | null;
}

export interface ChargeResult {
  approved: boolean;
  providerPaymentId?: string;
  declineReason?: string;
}

/** The provider-neutral shape our webhook handler reasons about. */
export type PaymentEventType =
  | 'payment_approved'
  | 'payment_declined'
  | 'payment_refunded'
  | 'payment_captured'
  /**
   * A hosted checkout ended WITHOUT a payment — abandoned, cancelled, or timed
   * out. Money never moved, so anything consumed up-front for this attempt
   * (account credit) must be returned.
   */
  | 'checkout_expired'
  /** A card was tokenised without a charge — the "change card" flow completing. */
  | 'instrument_stored'
  | 'unknown';

export interface PaymentEvent {
  id: string;
  type: PaymentEventType;
  providerPaymentId?: string;
  amountMinor?: number;
  currency?: string;
  /** Tokenised card returned after a `storeInstrument` payment. */
  paymentInstrumentId?: string;
  metadata: Record<string, string>;
}

export interface PaymentProviderPort {
  readonly name: string;

  /**
   * Whether this provider has the credentials to actually do anything.
   *
   * Exists so the billing page can degrade HONESTLY on an environment with no
   * keys: it shows what we truly know (the plan, the renewal date, the invoices —
   * all ours) and says the card actions are unavailable, rather than rendering a
   * "Change card" button that can only fail.
   */
  isConfigured(): boolean;

  /** Hosted page / payment link for a one-off charge (first payment of a sub too). */
  createHostedPayment(req: HostedPaymentRequest): Promise<HostedPaymentSession>;

  /** Merchant-initiated charge against a stored instrument (subscription renewal). */
  chargeStoredInstrument(req: RecurringChargeRequest): Promise<ChargeResult>;

  /** Hosted page that stores a card without charging it ("change card"). */
  createInstrumentSetup(req: InstrumentSetupRequest): Promise<InstrumentSetupSession>;

  /**
   * Brand/last4 of a stored card, for display. Returns null when it cannot be
   * resolved (no keys, provider unreachable, instrument gone) — the billing page
   * then says "card on file" rather than inventing a card that might not exist.
   */
  describeInstrument(paymentInstrumentId: string): Promise<StoredInstrument | null>;

  refund(providerPaymentId: string, amountMinor?: number): Promise<void>;

  /** Verifies the signature and normalises the payload. Throws if the signature is bad. */
  parseWebhook(rawBody: Buffer, signature: string): PaymentEvent;

  /**
   * Mirrors one catalogue row into the PSP's own product list, so its dashboard can
   * report by product instead of by an ad-hoc line description.
   *
   * Deliberately OPTIONAL, and deliberately ONE-WAY. It is a reporting convenience,
   * not a source of truth: the catalogue lives in `PricingPlan` and is edited in our
   * admin console, because it models things a PSP does not — three regional prices per
   * tier, a promo and a referral discount that compound, and an account-credit ledger.
   * A provider that cannot do this omits the method; nothing in the payment path
   * depends on it.
   *
   * Two-way sync is intentionally not offered. Two systems both accepting edits to a
   * price need conflict rules that, when they lose a race, charge somebody the wrong
   * amount.
   */
  syncCatalogEntry?(entry: CatalogEntry): Promise<CatalogSyncResult>;
}

/** One `PricingPlan` row, as the PSP needs to see it. */
export interface CatalogEntry {
  tier: string;
  region: string;
  interval: PriceInterval;
  currency: string;
  /** The LIST price. What a customer actually pays is computed per checkout. */
  unitAmount: number;
  displayName: string;
  description?: string | null;
  active: boolean;
  /** Existing provider ids, so a re-sync updates instead of duplicating. */
  existingProductId?: string | null;
  existingPriceId?: string | null;
}

export interface CatalogSyncResult {
  productId: string;
  priceId: string;
  /** True when the list price changed, so a replacement Price had to be created. */
  priceReplaced: boolean;
}

/** DI token — Nest cannot inject an interface. */
export const PAYMENT_PROVIDER = Symbol('PAYMENT_PROVIDER');

export const isRecurring = (i: PriceInterval) => i === 'MONTH' || i === 'YEAR';
