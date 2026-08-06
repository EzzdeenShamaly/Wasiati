import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { UPLOAD_PREFIXES } from './files.service';
import { STORAGE_PROVIDER, StorageProviderPort } from './storage-provider.interface';
import { CRON_LOCKS, withCronLock } from '../common/cron-lock';

/**
 * Reaps ORPHANED uploads: objects that were presigned + PUT to storage but never
 * `confirm`ed (so no FileObject row exists). Without this they consume storage
 * forever and evade the per-user quota. A nightly job deletes any object older than
 * the confirm window that has no matching FileObject.
 *
 * Storage residency: each regional deployment reaps its OWN bucket (the provider is
 * region-pinned), so this never crosses regions.
 */
@Injectable()
export class FilesReaperService {
  private readonly logger = new Logger(FilesReaperService.name);

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    @Inject(STORAGE_PROVIDER) private storage: StorageProviderPort,
  ) {}

  /** Hours an unconfirmed object may live before it's reaped. */
  private get graceHours(): number {
    return Number(this.config.get('UPLOAD_ORPHAN_GRACE_HOURS') ?? 24);
  }

  @Cron(CronExpression.EVERY_DAY_AT_1AM)
  async reapCron() {
    await withCronLock(this.prisma, CRON_LOCKS.filesReaper, 'files-reaper', () => this.reap());
  }

  async reap(now: Date = new Date()): Promise<{ scanned: number; deleted: number }> {
    if (!this.storage.configured) return { scanned: 0, deleted: 0 };

    // Every key we legitimately hold (confirmed). Anything in storage NOT here and
    // older than the grace window is an orphan.
    const confirmed = new Set((await this.prisma.fileObject.findMany({ select: { key: true } })).map((f) => f.key));
    const cutoff = now.getTime() - this.graceHours * 60 * 60 * 1000;

    let scanned = 0;
    let deleted = 0;
    for (const prefix of UPLOAD_PREFIXES) {
      const objects = await this.storage.listObjects(`${prefix}/`);
      scanned += objects.length;
      for (const obj of objects) {
        if (confirmed.has(obj.key)) continue; // a real, confirmed file
        if (new Date(obj.lastModified).getTime() >= cutoff) continue; // still within the grace window
        try {
          await this.storage.deleteObject(obj.key);
          deleted++;
        } catch (e) {
          this.logger.warn(`Failed to reap orphan ${obj.key}: ${(e as Error).message}`);
        }
      }
    }
    if (deleted > 0) this.logger.log(`Orphan reaper: deleted ${deleted} unconfirmed object(s) of ${scanned} scanned.`);
    return { scanned, deleted };
  }
}
