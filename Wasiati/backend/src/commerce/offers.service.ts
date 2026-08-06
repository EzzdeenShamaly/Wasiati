import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateOfferDto, UpdateOfferDto } from './dto/commerce.dto';

/** Admin-managed marketing offers/banners, shown in the app pricing screen. */
@Injectable()
export class OffersService {
  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.offer.findMany({ orderBy: [{ sortOrder: 'asc' }, { createdAt: 'desc' }] });
  }

  create(dto: CreateOfferDto, adminId: string) {
    return this.prisma.offer.create({
      data: {
        ...dto,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
        updatedBy: adminId,
      },
    });
  }

  async update(id: string, dto: UpdateOfferDto, adminId: string) {
    const existing = await this.prisma.offer.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Offer not found.');
    return this.prisma.offer.update({
      where: { id },
      data: {
        ...dto,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : undefined,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : undefined,
        updatedBy: adminId,
      },
    });
  }

  async remove(id: string) {
    await this.prisma.offer.delete({ where: { id } });
    return { deleted: true };
  }
}
