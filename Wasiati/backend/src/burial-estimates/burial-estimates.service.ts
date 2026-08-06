import { Injectable, ForbiddenException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { Region } from '@prisma/client';
import { regionRequiresPaidBurial } from '../common/geo.util';

/**
 * How long an already-answered (QUOTED) request stays visible in the admin queue, so
 * the admin can see their answer actually went out. Mirrors DECIDED_CLAIM_QUEUE_DAYS
 * on the death-claims queue.
 */
export const QUOTED_QUEUE_DAYS = 14;

/**
 * Ultimate tier burial-cost estimator — available only in regions where a grave must be
 * PAID for (see PAID_BURIAL_REGIONS). Where burial is free (KSA, QA) there is nothing to
 * pre-pay, so the feature is refused.
 *
 * Phase 1 is intentionally low-tech: we project today's typical local burial
 * cost forward using a historical inflation rate (funeral costs have run
 * ~3-6%/yr per industry data) so the client sees a realistic number — not a
 * guess. We do NOT automate actual booking or hold/underwrite funds; once a
 * client wants to proceed, this just flags the request for the admin to call
 * local mosques and get a real manually-sourced quote. No insurance/trust
 * licensing implications because Wasiati never touches the funeral funds.
 */
@Injectable()
export class BurialEstimatesService {
  private readonly DEFAULT_INFLATION_RATE = 4.0; // % per year, mid-range of industry data
  private readonly DEFAULT_PROJECTION_YEARS = 10;

  constructor(
    private prisma: PrismaService,
    private notifications: NotificationsService,
  ) {}

  private projectCost(baseAmount: number, inflationRatePercent: number, years: number): number {
    const rate = inflationRatePercent / 100;
    return Math.round(baseAmount * Math.pow(1 + rate, years) * 100) / 100;
  }

  async createEstimate(
    userId: string,
    region: Region,
    city: string,
    baseAmount: number,
    currency: 'USD' | 'CAD',
    inflationRatePercent?: number,
    projectionYears?: number,
  ) {
    // Gate on paid-burial regions (US/CA today), NOT a hardcoded "=== KSA" that let
    // Qatar (also free-burial) slip through.
    if (!regionRequiresPaidBurial(region)) {
      throw new ForbiddenException(
        'Burial pre-planning is only offered where a grave must be paid for. In your region burial is provided free, so there is nothing to pre-pay.',
      );
    }

    const rate = inflationRatePercent ?? this.DEFAULT_INFLATION_RATE;
    const years = projectionYears ?? this.DEFAULT_PROJECTION_YEARS;
    const projectedAmount = this.projectCost(baseAmount, rate, years);

    return this.prisma.burialEstimateRequest.create({
      data: {
        userId,
        region,
        city,
        baseAmount,
        currency,
        baseYear: new Date().getFullYear(),
        inflationRatePercent: rate,
        projectionYears: years,
        projectedAmount,
      },
    });
  }

  /** Client decides to actually pursue this — kicks off the manual mosque-outreach process. */
  async requestRealQuote(estimateId: string, userId: string) {
    const estimate = await this.prisma.burialEstimateRequest.findUnique({
      where: { id: estimateId },
      include: { user: true },
    });
    // Owner-scoped: look up by id, then verify ownership. A 404 (not 403) for anyone
    // else's estimate, matching the codebase's non-disclosure convention — without
    // this check any user could flip another's estimate and leak their email/city
    // into the admin mailbox.
    if (!estimate || estimate.userId !== userId) throw new NotFoundException('Estimate not found.');

    await this.prisma.burialEstimateRequest.update({
      where: { id: estimateId },
      data: { status: 'QUOTE_REQUESTED' },
    });

    // Notifies every admin (so a second/backup reviewer also sees this, not
    // just whoever happens to be the only one watching their inbox) — no
    // automated funeral-provider API call, this is a manual operational
    // task for now.
    const admins = await this.prisma.user.findMany({ where: { role: 'ADMIN' } });
    for (const admin of admins) {
      await this.notifications.sendEmail(
        admin.email,
        'New burial quote request — manual follow-up needed',
        `${estimate.user.email} in ${estimate.city}, ${estimate.region} requested a real quote. Estimated (inflation-adjusted) amount: ${estimate.projectedAmount} ${estimate.currency}. Please contact local mosques for an actual price.`,
      );
    }

    return { status: 'QUOTE_REQUESTED' };
  }

  /** Admin fills this in after manually calling around. */
  async submitManualQuote(estimateId: string, adminUserId: string, manualQuoteAmount: number, notes?: string) {
    const estimate = await this.prisma.burialEstimateRequest.findUnique({ where: { id: estimateId } });
    if (!estimate) throw new NotFoundException('Estimate not found.');

    return this.prisma.burialEstimateRequest.update({
      where: { id: estimateId },
      data: {
        status: 'QUOTED',
        manualQuoteAmount,
        manualQuoteNotes: notes,
        quotedBy: adminUserId,
        quotedAt: new Date(),
      },
    });
  }

  async listForUser(userId: string) {
    return this.prisma.burialEstimateRequest.findMany({ where: { userId } });
  }

  /**
   * The admin work queue — mirrors the death-claims queue (listPendingReview).
   *
   * Until this existed there was NO way to find a request awaiting a quote: the only
   * GET was scoped to the caller's own estimates, so a user could press "Request a
   * real quote", the row would sit at QUOTE_REQUESTED, and nobody could ever answer
   * it (the notification email was the sole trace, and an email is not a queue).
   *
   * QUOTE_REQUESTED rows are shown unconditionally, however old — each one is a
   * client waiting on a phone call. Recently QUOTED rows stay for QUOTED_QUEUE_DAYS,
   * keyed off quotedAt (not createdAt, or a slow answer would expire the moment it
   * was given), so the admin sees their answer went out. ESTIMATED rows are noise
   * (no human asked for anything) and never appear.
   */
  async listQuoteQueue() {
    const quotedCutoff = new Date(Date.now() - QUOTED_QUEUE_DAYS * 24 * 60 * 60 * 1000);
    return this.prisma.burialEstimateRequest.findMany({
      where: {
        OR: [
          { status: 'QUOTE_REQUESTED' },
          { status: 'QUOTED', quotedAt: { gte: quotedCutoff } },
        ],
      },
      // The admin has to CALL this person's local mosques — the queue is useless
      // without who they are and where.
      include: { user: { select: { id: true, email: true, phone: true, region: true } } },
      orderBy: { createdAt: 'asc' },
    });
  }
}
