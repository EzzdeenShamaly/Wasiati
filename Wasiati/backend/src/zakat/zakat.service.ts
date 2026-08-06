import { BadRequestException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AssetType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { REGION_CURRENCY, resolveBillingCurrency } from '../common/geo.util';
import { estimateZakat, isValidHawl, ZakatAsset, ZakatEstimate } from './zakat-calculator';
import { GoldPriceService } from './gold-price.service';

/** Admin-published link that gates the "Pay your zakah" button. */
export const ZAKAT_CHARITY_URL_KEY = 'zakat.charityUrl';

@Injectable()
export class ZakatService {
  private readonly logger = new Logger(ZakatService.name);

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    private goldPrice: GoldPriceService,
  ) {}

  /**
   * Price of one gram of gold, in MINOR units of `currency` — LIVE first.
   *
   * GoldPriceService refreshes a keyless spot feed every six hours and refuses to
   * serve anything older than 72h; the ZAKAT_GOLD_PRICE_PER_GRAM_<CUR> env values
   * are the manual fallback for a dead feed, no longer the primary source.
   *
   * Still deliberately NO default. Niṣāb is the line between owing zakat and owing
   * nothing; a guessed or stale gold price would tell someone they owe money they do
   * not, or that they owe none when they do. Live stale AND env absent = a clean 503.
   */
  private async goldPricePerGramMinor(currency: string): Promise<number> {
    const live = await this.goldPrice.livePricePerGramMinor(currency);
    if (live != null) return live;

    const raw = this.config.get<string>(`ZAKAT_GOLD_PRICE_PER_GRAM_${currency.toUpperCase()}`);
    const value = Number(raw);
    if (!raw || !Number.isFinite(value) || value <= 0) {
      throw new ServiceUnavailableException(
        `The zakat estimate is unavailable: no current gold price is available for ${currency}.`,
      );
    }
    return Math.round(value);
  }

  /** The charity link, or null. No link published means no "Pay your zakah" button. */
  async charityUrl(): Promise<string | null> {
    const row = await this.prisma.appSetting.findUnique({ where: { key: ZAKAT_CHARITY_URL_KEY } });
    const value = row?.value?.trim();
    return value ? value : null;
  }

  async setCharityUrl(url: string | null, adminUserId: string): Promise<{ url: string | null }> {
    const trimmed = url?.trim() ?? '';
    if (trimmed && !/^https:\/\//i.test(trimmed)) {
      // We are sending users to hand over money. Plain http is not acceptable.
      throw new BadRequestException('The charity link must be an https:// URL.');
    }
    await this.prisma.appSetting.upsert({
      where: { key: ZAKAT_CHARITY_URL_KEY },
      create: { key: ZAKAT_CHARITY_URL_KEY, value: trimmed, updatedBy: adminUserId },
      update: { value: trimmed, updatedBy: adminUserId },
    });
    this.logger.log(`Zakat charity link ${trimmed ? 'published' : 'cleared'} by ${adminUserId}.`);
    return { url: trimmed || null };
  }

  /** Stores the user's Hijri ḥawl anniversary. Gregorian input is rejected upstream. */
  async setHawl(userId: string, day: number, month: number) {
    if (!isValidHawl(day, month)) {
      throw new BadRequestException('The ḥawl date must be a Hijri day (1–30) and month (1–12).');
    }
    await this.prisma.user.update({ where: { id: userId }, data: { hawlDay: day, hawlMonth: month } });
    return { hawlDay: day, hawlMonth: month };
  }

  /**
   * The user's zakat estimate across every asset on every will they own.
   *
   * Assets carry their own currency; totals are stated in the user's own currency.
   * Anything that cannot be converted exactly is disclosed, never guessed at.
   */
  async estimate(userId: string): Promise<
    ZakatEstimate & {
      hawl: { day: number; month: number } | null;
      charityUrl: string | null;
      isEstimate: true;
    }
  > {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found.');

    const currency = resolveBillingCurrency(user.region) || REGION_CURRENCY[user.region];
    const goldPrice = await this.goldPricePerGramMinor(currency);

    const rows = await this.prisma.asset.findMany({
      where: { will: { ownerId: userId } },
      select: { type: true, estimatedValue: true, currency: true },
    });

    const assets: ZakatAsset[] = rows
      .filter((r) => r.estimatedValue != null)
      .map((r) => ({
        type: r.type as AssetType,
        // Decimal(14,2) -> minor units.
        amountMinor: Math.round(Number(r.estimatedValue) * 100),
        currency: (r.currency ?? currency).toUpperCase(),
      }));

    const estimate = estimateZakat({ assets, currency, goldPricePerGramMinor: goldPrice });

    return {
      ...estimate,
      hawl: user.hawlDay && user.hawlMonth ? { day: user.hawlDay, month: user.hawlMonth } : null,
      charityUrl: await this.charityUrl(),
      isEstimate: true,
    };
  }
}
