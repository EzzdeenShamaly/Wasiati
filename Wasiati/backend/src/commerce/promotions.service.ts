import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, PromotionType, Region, SubscriptionTier } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { resolveBillingCurrency } from '../common/geo.util';
import { CreatePromotionDto, UpdatePromotionDto } from './dto/commerce.dto';

export interface PromoValidation {
  valid: boolean;
  reason?: string;
  code?: string;
  type?: string;
  value?: number;
  currency?: string | null;
  description?: string | null;
}

/**
 * Admin-managed promotions.
 *
 * Discounts are computed and applied by US, at checkout (`applyToAmount`), rather
 * than mirrored into a provider coupon object — Stripe has Coupons, but using them
 * would tie the discount lifecycle to the PSP. The provider only ever sees a final
 * amount to charge.
 */
@Injectable()
export class PromotionsService {
  private readonly logger = new Logger(PromotionsService.name);

  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.promotion.findMany({ orderBy: { createdAt: 'desc' } });
  }

  /** A PERCENT promo above 100 would drive the price negative (floored to 0 = a free
   *  plan). `value` is dual-purpose (percent OR minor-unit amount) so the ceiling can't
   *  live on the DTO; enforce it here for both create and update. */
  private static assertPercentBound(type: PromotionType | undefined, value: number | undefined) {
    if (type === PromotionType.PERCENT && value !== undefined && value > 100) {
      throw new BadRequestException('A percentage promotion cannot exceed 100.');
    }
  }

  async create(dto: CreatePromotionDto, adminId: string) {
    PromotionsService.assertPercentBound(dto.type, dto.value);
    const promo = await this.prisma.promotion.create({
      data: {
        code: dto.code.toUpperCase().trim(),
        type: dto.type,
        value: dto.value,
        currency: dto.currency?.toUpperCase(),
        appliesToTiers: dto.appliesToTiers ?? [],
        appliesToRegions: dto.appliesToRegions ?? [],
        description: dto.description,
        maxRedemptions: dto.maxRedemptions,
        firstTimeOnly: dto.firstTimeOnly ?? false,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
        active: dto.active ?? true,
        updatedBy: adminId,
      },
    });
    return promo;
  }

  async update(id: string, dto: UpdatePromotionDto, adminId: string) {
    const existing = await this.prisma.promotion.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Promotion not found.');
    // Guard against a PERCENT promo (existing or newly-set type) being pushed over 100.
    PromotionsService.assertPercentBound(dto.type ?? existing.type, dto.value ?? existing.value);
    return this.prisma.promotion.update({
      where: { id },
      data: {
        ...dto,
        code: dto.code ? dto.code.toUpperCase().trim() : undefined,
        currency: dto.currency?.toUpperCase(),
        // Pass null THROUGH, don't swallow it: undefined = leave unchanged, explicit
        // null = clear (make the window open-ended). The old `dto.startsAt ? … :
        // undefined` turned a clear into a no-op, so a date once set could never be
        // removed via PATCH.
        startsAt: dto.startsAt != null ? new Date(dto.startsAt) : dto.startsAt,
        endsAt: dto.endsAt != null ? new Date(dto.endsAt) : dto.endsAt,
        updatedBy: adminId,
      },
    });
  }

  /**
   * Archives a promotion instead of destroying it, so an admin can reinstate it.
   *
   * This used to be `prisma.promotion.delete()`. That was irreversible and lossy: it
   * discarded `timesRedeemed` (the only record of how many customers used the code) and
   * orphaned any `Offer.promotionId` pointing at it — that column is a bare String with
   * no foreign key, so nothing at the DB level stops the reference from dangling. A
   * mistaken click on a live code could not be undone.
   *
   * `active: false` is the archived state: validate() already refuses an inactive code
   * on its first check, so archiving takes effect at checkout immediately. Reinstating is
   * [reinstate] (or a PATCH with active: true) and restores the code with its redemption
   * history intact — which matters, because a reinstated code with a maxRedemptions cap
   * must resume counting from where it stopped, not from zero.
   */
  async archive(id: string, adminId: string) {
    const existing = await this.prisma.promotion.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Promotion not found.');
    await this.prisma.promotion.update({
      where: { id },
      data: { active: false, updatedBy: adminId },
    });
    return { archived: true, reinstatable: true };
  }

  /** Brings an archived promotion back, redemption count and limits untouched. */
  async reinstate(id: string, adminId: string) {
    const existing = await this.prisma.promotion.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Promotion not found.');
    await this.prisma.promotion.update({
      where: { id },
      data: { active: true, updatedBy: adminId },
    });
    return { active: true };
  }

  /**
   * Applies a code to a plan's price and returns the amount actually payable.
   *
   * No provider coupon object is mirrored — the discount is computed here and
   * the provider only ever sees a final amount. An invalid code is a no-op
   * rather than an error — the customer simply pays full price.
   *
   * Never returns a negative amount: a 100%-off or oversized AMOUNT code floors at 0.
   */
  async applyToAmount(
    code: string,
    plan: { unitAmount: number; currency: string; tier: SubscriptionTier; region: Region },
    // Required, not optional: this is the money path, and a firstTimeOnly code is only
    // actually enforced when a user is supplied. Making the caller pass it means a new
    // call site cannot silently skip the check the way an optional argument would.
    userId: string,
  ): Promise<{ amountMinor: number; promotionId: string | null; rejectedReason?: string }> {
    const check = await this.validate(code, plan.tier, plan.region, userId);
    if (!check.valid) {
      // Say WHY, both to the caller and to the log. This used to return full price with
      // no reason and no log line, so a code the preview had called valid (the preview
      // omits tier, this check does not) silently became a full-price charge — the
      // customer saw "25% off" and paid 100%, and nothing anywhere recorded it.
      this.logger.warn(
        `Promo "${code}" rejected at checkout for user ${userId} (${plan.tier}/${plan.region}): ${check.reason}`,
      );
      return { amountMinor: plan.unitAmount, promotionId: null, rejectedReason: check.reason };
    }

    const promo = await this.prisma.promotion.findUnique({ where: { code: code.toUpperCase().trim() } });
    if (!promo) {
      this.logger.warn(`Promo "${code}" vanished between validation and application (user ${userId}).`);
      return { amountMinor: plan.unitAmount, promotionId: null, rejectedReason: 'This code is not valid.' };
    }

    let amount = plan.unitAmount;
    if (promo.type === 'PERCENT') {
      amount = Math.round(plan.unitAmount * (1 - promo.value / 100));
    } else {
      // An AMOUNT promo only applies in its own currency, otherwise it is meaningless.
      // validate() now checks this too, so the preview and this path agree; the guard
      // stays as the money path's own backstop.
      if (promo.currency && promo.currency.toUpperCase() !== plan.currency.toUpperCase()) {
        this.logger.warn(
          `Promo "${code}" is in ${promo.currency} but the plan bills in ${plan.currency} (user ${userId}).`,
        );
        return {
          amountMinor: plan.unitAmount,
          promotionId: null,
          rejectedReason: 'This code cannot be used in your billing currency.',
        };
      }
      amount = plan.unitAmount - promo.value;
    }

    return { amountMinor: Math.max(0, amount), promotionId: promo.id };
  }

  /**
   * Increments the redemption counter once per successful payment.
   *
   * Idempotent per payment: Stripe fires both `checkout.session.completed` and
   * `payment_intent.succeeded` for one paid session, each with its own event id (so the
   * per-event webhook guard clears twice) but the same PaymentIntent as `providerPaymentId`.
   * Without a per-payment key the counter double-counts and a `maxRedemptions`-limited
   * promo exhausts at half its intended uses. We claim a marker row keyed on the payment
   * id and increment in the SAME transaction, so the two commit together or not at all.
   */
  async recordRedemption(promotionId: string, providerPaymentId?: string) {
    // No stable payment id (shouldn't happen for a real payment) — best-effort increment.
    if (!providerPaymentId) {
      await this.prisma.promotion.update({
        where: { id: promotionId },
        data: { timesRedeemed: { increment: 1 } },
      });
      return;
    }

    try {
      await this.prisma.$transaction(async (tx) => {
        // Reuse the payment-event idempotency table as the per-payment marker; a synthetic
        // key can't collide with a real provider event id.
        await tx.processedPaymentEvent.create({
          data: { id: `redeem:${promotionId}:${providerPaymentId}`, type: 'promo_redemption' },
        });
        await tx.promotion.update({
          where: { id: promotionId },
          data: { timesRedeemed: { increment: 1 } },
        });
      });
    } catch (e) {
      // Marker already present → this payment was already counted; do not increment again.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') return;
      throw e;
    }
  }

  /**
   * Has this account ever completed a purchase?
   *
   * An Invoice is written once per payment that actually settled, so its existence is
   * the honest signal. REFUNDED counts: the customer did buy, and a refund must not
   * make them a "first-time" buyer again — otherwise buy/refund/rebuy farms the code.
   */
  private async hasPurchasedBefore(userId: string): Promise<boolean> {
    const prior = await this.prisma.invoice.findFirst({ where: { userId }, select: { id: true } });
    return prior !== null;
  }

  /**
   * Public preview: is this code usable for the given tier/region right now?
   *
   * [userId] is optional because this doubles as the anonymous pricing-page preview.
   * When it is absent a `firstTimeOnly` code is previewed OPTIMISTICALLY — a visitor who
   * has not signed in yet usually IS a first-time buyer, and telling them their launch
   * code is invalid would be both wrong and a reason not to sign up. The money path
   * ([applyToAmount]) always has a user and always enforces, so an optimistic preview
   * can never turn into an unearned discount.
   */
  async validate(
    code: string,
    tier?: SubscriptionTier,
    region?: Region,
    userId?: string,
  ): Promise<PromoValidation> {
    const promo = await this.prisma.promotion.findUnique({ where: { code: code.toUpperCase().trim() } });
    if (!promo || !promo.active) return { valid: false, reason: 'This code is not valid.' };
    const now = new Date();
    if (promo.startsAt && promo.startsAt > now) return { valid: false, reason: 'This code is not active yet.' };
    if (promo.endsAt && promo.endsAt < now) return { valid: false, reason: 'This code has expired.' };
    if (promo.maxRedemptions && promo.timesRedeemed >= promo.maxRedemptions) {
      return { valid: false, reason: 'This code has been fully redeemed.' };
    }
    if (promo.firstTimeOnly && userId && (await this.hasPurchasedBefore(userId))) {
      return { valid: false, reason: 'This code is for a first subscription only.' };
    }
    if (promo.appliesToTiers.length && tier && !promo.appliesToTiers.includes(tier)) {
      return { valid: false, reason: 'This code does not apply to the selected plan.' };
    }
    if (promo.appliesToRegions.length && region && !promo.appliesToRegions.includes(region)) {
      return { valid: false, reason: 'This code is not available in your region.' };
    }
    // An AMOUNT code is denominated in one currency and is meaningless in another —
    // applyToAmount has always dropped it, but this check lived ONLY there, so the
    // preview called it valid and checkout then charged full price with no explanation.
    // Checked here too, against the region's billing currency, so the two agree.
    if (promo.type === 'AMOUNT' && promo.currency && region) {
      const billing = resolveBillingCurrency(region);
      if (promo.currency.toUpperCase() !== billing.toUpperCase()) {
        return { valid: false, reason: 'This code cannot be used in your billing currency.' };
      }
    }
    return {
      valid: true,
      code: promo.code,
      type: promo.type,
      value: promo.value,
      currency: promo.currency,
      description: promo.description,
    };
  }

}
