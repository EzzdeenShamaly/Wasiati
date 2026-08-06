import { BadRequestException, Injectable } from '@nestjs/common';
import { DirectiveStatus, DirectiveType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../common/audit/audit.service';
import { SaveDirectiveDto } from './dto/directive.dto';

/**
 * Directives beyond the will (financial POA / healthcare directive). User-scoped,
 * one document per type: every query runs through the caller's userId, so there is
 * no cross-owner surface to hide behind a NotFound the way will-scoped modules do.
 *
 * Save IS sign. The UI's only action is "Save & sign" (disabled until complete),
 * so the endpoint validates completeness and executes the document in one step —
 * and editing a signed directive re-executes it, stamping a fresh signedAt, the
 * same way the prototype re-signs on every save. These documents never enter the
 * exported will PDF: they are effective in life, not at death.
 */
@Injectable()
export class DirectivesService {
  constructor(
    private prisma: PrismaService,
    private audit: AuditService,
  ) {}

  private clean(v: string | undefined, max: number): string {
    return typeof v === 'string' ? v.trim().slice(0, max) : '';
  }

  list(userId: string) {
    return this.prisma.directiveDocument.findMany({ where: { userId }, orderBy: { type: 'asc' } });
  }

  async save(userId: string, type: DirectiveType, dto: SaveDirectiveDto) {
    const agentName = this.clean(dto.agentName, 120);
    const agentPhone = this.clean(dto.agentPhone, 40);
    const agentEmail = this.clean(dto.agentEmail, 200);
    // HCD carries the treatment wishes; a POA has no wishes field at all.
    const wishes = type === DirectiveType.HCD ? this.clean(dto.wishes, 2000) : null;

    if (!agentName || !agentPhone || !agentEmail) {
      throw new BadRequestException('The agent’s full name, phone and email are all required to sign.');
    }
    if (type === DirectiveType.HCD && !wishes) {
      throw new BadRequestException('Treatment wishes are required to sign a healthcare directive.');
    }

    const signedAt = new Date();
    const data = { agentName, agentPhone, agentEmail, wishes, status: DirectiveStatus.SIGNED, signedAt };
    const doc = await this.prisma.directiveDocument.upsert({
      where: { userId_type: { userId, type } },
      create: { userId, type, ...data },
      update: data,
    });

    await this.audit.log({
      actorId: userId,
      action: 'directive.sign',
      targetType: 'DirectiveDocument',
      targetId: doc.id,
      metadata: { type },
    });
    return doc;
  }
}
