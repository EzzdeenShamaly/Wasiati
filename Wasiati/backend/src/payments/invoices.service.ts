import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PriceInterval, Prisma, SubscriptionTier } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { InvoiceDocumentService } from './invoice-document.service';

/**
 * The customer's receipts.
 *
 * These are OURS, not the PSP's. Because we deliberately run our own billing cycle
 * (no Stripe Billing — see PaymentsService), Stripe has no Invoice object to list:
 * a renewal is a bare PaymentIntent and a credit-covered purchase never reaches the
 * provider at all. So the "Manage billing" invoice list can only be truthful if we
 * record every payment ourselves, at the three places money is actually taken:
 * the approved-payment webhook, a credit-covered checkout, and each renewal.
 */
@Injectable()
export class InvoicesService {
  private readonly logger = new Logger(InvoicesService.name);

  constructor(
    private prisma: PrismaService,
    private documents: InvoiceDocumentService,
  ) {}

  /**
   * Writes a receipt for money (or credit) already taken.
   *
   * Idempotent by construction: `idempotencyKey` is unique, so one payment is one
   * invoice even though Stripe fires both checkout.session.completed AND
   * payment_intent.succeeded for a single paid session.
   *
   * NEVER throws into the caller. The payment has already happened by the time this
   * runs; failing the caller would either fail a completed purchase or send the
   * provider into a retry loop that re-fulfils it. A lost receipt is recoverable
   * from the provider's own records — a double-charge is not. Logged loudly.
   */
  async record(data: {
    userId: string;
    idempotencyKey: string;
    description: string;
    /** Total value INCLUDING any part paid from account credit. MINOR units. */
    amountMinor: number;
    currency: string;
    creditAppliedMinor?: number;
    tier?: SubscriptionTier | null;
    interval?: PriceInterval | null;
    providerPaymentId?: string;
  }): Promise<void> {
    try {
      await this.prisma.invoice.create({
        data: {
          userId: data.userId,
          idempotencyKey: data.idempotencyKey,
          description: data.description,
          amountMinor: data.amountMinor,
          currency: data.currency.toUpperCase(),
          creditAppliedMinor: data.creditAppliedMinor ?? 0,
          tier: data.tier ?? undefined,
          interval: data.interval ?? undefined,
          providerPaymentId: data.providerPaymentId,
        },
      });
    } catch (e) {
      // Already recorded (the paired event) — the expected, uninteresting case.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') return;
      this.logger.error(`Could not record invoice ${data.idempotencyKey} for ${data.userId}: ${(e as Error).message}`);
    }
  }

  /** The user's receipts, newest first. */
  async listForUser(userId: string) {
    const invoices = await this.prisma.invoice.findMany({
      where: { userId },
      orderBy: { issuedAt: 'desc' },
      take: 100,
    });
    return invoices.map((i) => ({
      id: i.id,
      issuedAt: i.issuedAt,
      description: i.description,
      amountMinor: i.amountMinor,
      currency: i.currency,
      creditAppliedMinor: i.creditAppliedMinor,
      /** What the card was actually charged; 0 when credit covered the lot. */
      chargedMinor: Math.max(0, i.amountMinor - i.creditAppliedMinor),
      status: i.status,
      tier: i.tier,
      interval: i.interval,
    }));
  }

  /** Renders one of the user's OWN invoices as a PDF. */
  async pdfForUser(userId: string, invoiceId: string): Promise<{ pdf: Buffer; filename: string }> {
    // Scoped by userId, so another customer's invoice id is indistinguishable from
    // a nonexistent one — this cannot be used to confirm someone else's purchase.
    const invoice = await this.prisma.invoice.findFirst({
      where: { id: invoiceId, userId },
      include: { user: { select: { email: true } } },
    });
    if (!invoice) throw new NotFoundException('Invoice not found.');

    const pdf = await this.documents.renderPdf({
      id: invoice.id,
      issuedAt: invoice.issuedAt,
      description: invoice.description,
      amountMinor: invoice.amountMinor,
      currency: invoice.currency,
      creditAppliedMinor: invoice.creditAppliedMinor,
      status: invoice.status,
      billedToEmail: invoice.user.email,
      tier: invoice.tier,
      interval: invoice.interval,
      refundedAt: invoice.refundedAt,
    });
    return { pdf, filename: `wasiati-invoice-${invoice.id}.pdf` };
  }

  /**
   * A refunded payment's receipt must stop claiming the customer paid.
   *
   * updateMany, not update: the invoice may legitimately not exist (a purchase from
   * before receipts were recorded), and a refund must never fail over a receipt.
   */
  async markRefunded(providerPaymentId: string): Promise<void> {
    try {
      await this.prisma.invoice.updateMany({
        where: { idempotencyKey: providerPaymentId },
        data: { status: 'REFUNDED', refundedAt: new Date() },
      });
    } catch (e) {
      this.logger.error(`Could not mark invoice ${providerPaymentId} refunded: ${(e as Error).message}`);
    }
  }
}
