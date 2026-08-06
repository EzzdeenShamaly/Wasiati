import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export interface AuditEntry {
  actorId?: string;
  actorRole?: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  region?: string;
}

/**
 * Append-only audit trail for privileged / security-sensitive actions.
 * Writes never throw into the request path — a failed audit write is logged and
 * swallowed so it can't break the operation being audited.
 */
@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private prisma: PrismaService) {}

  async log(entry: AuditEntry): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: entry.actorId,
          actorRole: entry.actorRole,
          action: entry.action,
          targetType: entry.targetType,
          targetId: entry.targetId,
          metadata: (entry.metadata as any) ?? undefined,
          ipAddress: entry.ipAddress,
          userAgent: entry.userAgent,
          region: entry.region,
        },
      });
    } catch (e) {
      this.logger.warn(`Audit write failed for "${entry.action}": ${(e as Error).message}`);
    }
  }
}
