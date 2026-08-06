import { BadRequestException, Inject, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PAYMENT_PROVIDER, PaymentProviderPort } from './payment-provider.interface';

export interface CatalogSyncRow {
  plan: string;
  productId?: string;
  priceId?: string;
  priceReplaced?: boolean;
  error?: string;
}

export interface CatalogSyncReport {
  synced: number;
  failed: number;
  pricesReplaced: number;
  rows: CatalogSyncRow[];
}

/**
 * Pushes the catalogue into the payment provider's own product list, one way.
 *
 * The direction is the whole design. `PricingPlan` is the source of truth and stays
 * that way: it holds three regional prices per tier, and the price a customer actually
 * pays is computed at checkout from a promo and a referral discount that compound and
 * then account credit — none of which a PSP's catalogue can express. Mirroring exists
 * so the provider's dashboard can report by product rather than by a throwaway line
 * description, which is the one thing an empty PSD catalogue actually costs you.
 *
 * A price edited in the provider's dashboard is therefore overwritten by the next sync.
 * That is deliberate: the alternative is a dashboard edit silently changing what
 * customers are charged without touching our catalogue, our admin audit trail, or the
 * numbers on the pricing page.
 *
 * Inactive rows are synced too, deactivated rather than deleted, so a retired plan
 * (Basic, Ultimate one-time) stops being sellable in both places while its history
 * still resolves.
 */
@Injectable()
export class CatalogSyncService {
  private readonly logger = new Logger(CatalogSyncService.name);

  constructor(
    private prisma: PrismaService,
    @Inject(PAYMENT_PROVIDER) private provider: PaymentProviderPort,
  ) {}

  get supported(): boolean {
    return typeof this.provider.syncCatalogEntry === 'function' && this.provider.isConfigured();
  }

  async sync(): Promise<CatalogSyncReport> {
    if (typeof this.provider.syncCatalogEntry !== 'function') {
      throw new BadRequestException(`${this.provider.name} cannot mirror a catalogue.`);
    }
    if (!this.provider.isConfigured()) {
      throw new BadRequestException('The payment provider is not configured on this server.');
    }

    const plans = await this.prisma.pricingPlan.findMany({
      orderBy: [{ region: 'asc' }, { sortOrder: 'asc' }, { interval: 'asc' }],
    });

    const rows: CatalogSyncRow[] = [];
    let synced = 0;
    let failed = 0;
    let pricesReplaced = 0;

    for (const plan of plans) {
      const label = `${plan.tier}/${plan.region}/${plan.interval}`;
      try {
        const res = await this.provider.syncCatalogEntry({
          tier: plan.tier,
          region: plan.region,
          interval: plan.interval,
          currency: plan.currency,
          unitAmount: plan.unitAmount,
          displayName: plan.displayName,
          description: plan.description,
          active: plan.active,
          existingProductId: plan.providerProductId,
          existingPriceId: plan.providerPriceId,
        });
        // Persisted so the next sync updates rather than duplicating, and so checkout
        // can name the product on the line item.
        await this.prisma.pricingPlan.update({
          where: { id: plan.id },
          data: { providerProductId: res.productId, providerPriceId: res.priceId },
        });
        if (res.priceReplaced) pricesReplaced++;
        synced++;
        rows.push({ plan: label, productId: res.productId, priceId: res.priceId, priceReplaced: res.priceReplaced });
      } catch (e: any) {
        // One bad row must not abort the rest — a partial mirror is still useful, and
        // the report says exactly which rows to look at.
        failed++;
        const message = String(e?.message ?? e).slice(0, 200);
        rows.push({ plan: label, error: message });
        this.logger.warn(`Catalogue sync failed for ${label}: ${message}`);
      }
    }

    this.logger.log(`Catalogue sync: ${synced} synced, ${failed} failed, ${pricesReplaced} price(s) replaced.`);
    return { synced, failed, pricesReplaced, rows };
  }

  /** What is mirrored today, without calling the provider — for the admin screen. */
  async status() {
    const plans = await this.prisma.pricingPlan.findMany({ select: { active: true, providerProductId: true } });
    const active = plans.filter((p) => p.active);
    return {
      supported: this.supported,
      provider: this.provider.name,
      totalPlans: plans.length,
      activePlans: active.length,
      mirrored: plans.filter((p) => p.providerProductId).length,
      activeUnmirrored: active.filter((p) => !p.providerProductId).length,
    };
  }
}
