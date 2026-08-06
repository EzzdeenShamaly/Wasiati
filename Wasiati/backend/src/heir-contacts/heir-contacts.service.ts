import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { WillStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateHeirContactDto, UpdateHeirContactDto } from './dto/heir-contact.dto';

/**
 * The heir registry (create-flow step 2): contact details per heir so the will
 * can be released to each of them at claim time. Owner-scoped CRUD; a NotFound
 * (never Forbidden) hides another owner's will, matching WillsService. Rows are
 * editable only while the will is a DRAFT — a sealed will's roster is frozen with
 * the rest of its content (reopen to edit), exactly like bequests and the message.
 */
@Injectable()
export class HeirContactsService {
  constructor(private prisma: PrismaService) {}

  /** Owner check only (read paths). NotFound hides another user's will. */
  private async assertOwner(willId: string, ownerId: string): Promise<void> {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
  }

  /** Owner + editability check (write paths): a locked/non-DRAFT will is frozen. */
  private async assertEditable(willId: string, ownerId: string): Promise<void> {
    const will = await this.prisma.will.findUnique({
      where: { id: willId },
      select: { ownerId: true, status: true, locked: true },
    });
    if (!will || will.ownerId !== ownerId) throw new NotFoundException('Will not found.');
    if (will.locked || will.status !== WillStatus.DRAFT) {
      throw new ForbiddenException('Heir contacts can only be edited while the will is a draft.');
    }
  }

  private clean(v: string | undefined, max: number): string | null {
    if (typeof v !== 'string') return null;
    const t = v.trim().slice(0, max);
    return t.length ? t : null;
  }

  async list(willId: string, ownerId: string) {
    await this.assertOwner(willId, ownerId);
    return this.prisma.willHeirContact.findMany({ where: { willId }, orderBy: { createdAt: 'asc' } });
  }

  async create(willId: string, ownerId: string, dto: CreateHeirContactDto) {
    await this.assertEditable(willId, ownerId);
    return this.prisma.willHeirContact.create({
      data: {
        willId,
        relation: dto.relation,
        name: this.clean(dto.name, 120) ?? '',
        phone: this.clean(dto.phone, 40),
        email: this.clean(dto.email, 200),
        isMinor: dto.isMinor ?? false,
      },
    });
  }

  async update(willId: string, ownerId: string, id: string, dto: UpdateHeirContactDto) {
    await this.assertEditable(willId, ownerId);
    // Scope the update to (id, willId) so a caller can never touch another will's
    // row by id alone — the will was already proven to be theirs above.
    const data: Record<string, unknown> = {};
    if (dto.relation !== undefined) data.relation = dto.relation;
    if (dto.name !== undefined) data.name = this.clean(dto.name, 120) ?? '';
    if (dto.phone !== undefined) data.phone = this.clean(dto.phone, 40);
    if (dto.email !== undefined) data.email = this.clean(dto.email, 200);
    if (dto.isMinor !== undefined) data.isMinor = dto.isMinor;
    const res = await this.prisma.willHeirContact.updateMany({ where: { id, willId }, data });
    if (res.count === 0) throw new NotFoundException('Heir contact not found.');
    return this.prisma.willHeirContact.findUniqueOrThrow({ where: { id } });
  }

  async remove(willId: string, ownerId: string, id: string) {
    await this.assertEditable(willId, ownerId);
    const res = await this.prisma.willHeirContact.deleteMany({ where: { id, willId } });
    if (res.count === 0) throw new NotFoundException('Heir contact not found.');
    return { deleted: true };
  }
}
