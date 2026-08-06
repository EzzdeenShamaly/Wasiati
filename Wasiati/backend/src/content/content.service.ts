import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Admin Content tab (spec §7).
 *
 * User-facing strings, EN + AR, published live. The app ships the ARB bundle as its
 * compile-time default and merges these overrides on top (docs/DECISIONS.md §4), so
 * a string — including the legal disclaimer — can be corrected without an app
 * release. Every edit writes an append-only revision, so the history of a legal
 * string is always reconstructable.
 */
export interface LocalizedValue {
  en: string;
  ar: string;
}

@Injectable()
export class ContentService {
  private readonly logger = new Logger(ContentService.name);

  constructor(private prisma: PrismaService) {}

  /**
   * The PUBLISHED overrides only, as { key: { en, ar } }. This is what the app
   * fetches at launch and merges over its bundled strings. Unpublished drafts are
   * never served to end users.
   */
  async publishedOverrides(): Promise<Record<string, LocalizedValue>> {
    const rows = await this.prisma.contentString.findMany({ where: { published: true } });
    const out: Record<string, LocalizedValue> = {};
    for (const r of rows) out[r.key] = { en: r.valueEn, ar: r.valueAr };
    return out;
  }

  /** Admin view: every string, published or not, plus its last editor + time. */
  async listAll() {
    return this.prisma.contentString.findMany({ orderBy: { key: 'asc' } });
  }

  /** The audit trail for one key, newest first. */
  async revisions(key: string) {
    return this.prisma.contentRevision.findMany({
      where: { key },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * Publishes (or updates) one string. Writes the new value AND an audit revision in
   * a single transaction, so a published change can never exist without its audit
   * line. Both EN and AR are required — a half-translated override would show English
   * to Arabic users or vice versa.
   */
  async upsert(
    key: string,
    data: { en: string; ar: string; note?: string; published?: boolean },
    adminUserId: string,
  ) {
    const en = data.en?.trim();
    const ar = data.ar?.trim();
    if (!key?.trim()) throw new BadRequestException('A content key is required.');
    if (!en || !ar) throw new BadRequestException('Both English and Arabic values are required.');

    const [row] = await this.prisma.$transaction([
      this.prisma.contentString.upsert({
        where: { key },
        create: { key, valueEn: en, valueAr: ar, note: data.note, published: data.published ?? true, updatedBy: adminUserId },
        update: { valueEn: en, valueAr: ar, note: data.note, published: data.published ?? true, updatedBy: adminUserId },
      }),
      this.prisma.contentRevision.create({
        data: { key, valueEn: en, valueAr: ar, editedBy: adminUserId },
      }),
    ]);

    this.logger.log(`Content "${key}" ${row.published ? 'published' : 'saved as draft'} by ${adminUserId}.`);
    return row;
  }

  /** Removes an override so the app falls back to its bundled ARB string. The audit
   *  revisions are cascade-deleted with it; the act itself is logged. */
  async remove(key: string, adminUserId: string) {
    const existing = await this.prisma.contentString.findUnique({ where: { key } });
    if (!existing) return { removed: false };
    await this.prisma.contentString.delete({ where: { key } });
    this.logger.warn(`Content override "${key}" removed by ${adminUserId} — reverts to the bundled string.`);
    return { removed: true };
  }
}
