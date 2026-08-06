import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException('User not found.');
    const { passwordHash, mfaSecret, ...safe } = user;
    return safe;
  }

  /** Admin users table + aggregate stats for the admin dashboard charts. */
  async listForAdmin() {
    const users = await this.prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        email: true,
        phone: true,
        region: true,
        role: true,
        idVerificationStatus: true,
        emailVerified: true,
        compTier: true,
        createdAt: true,
      },
    });

    // Most recent IP per user, from the audit trail.
    const logs = await this.prisma.auditLog.findMany({
      where: { actorId: { in: users.map((u) => u.id) }, ipAddress: { not: null } },
      orderBy: { createdAt: 'desc' },
      select: { actorId: true, ipAddress: true },
    });
    const ipByUser = new Map<string, string>();
    for (const l of logs) {
      if (l.actorId && !ipByUser.has(l.actorId)) ipByUser.set(l.actorId, l.ipAddress as string);
    }

    const tally = (pick: (u: (typeof users)[number]) => string) =>
      users.reduce<Record<string, number>>((acc, u) => {
        const k = pick(u);
        acc[k] = (acc[k] ?? 0) + 1;
        return acc;
      }, {});

    // Each user's plan for the admin table = their highest active-subscription tier
    // (one-time purchases also record an ACTIVE non-renewing Subscription). No active
    // subscription => free.
    const activeSubs = await this.prisma.subscription.findMany({
      where: { status: 'ACTIVE' },
      select: { userId: true, tier: true },
    });
    const tierRank: Record<string, number> = { BASIC: 1, STANDARD: 2, PREMIUM: 3, ULTIMATE: 4 };
    const planByUser = new Map<string, string>();
    for (const s of activeSubs) {
      const cur = planByUser.get(s.userId);
      if (!cur || (tierRank[s.tier] ?? 0) > (tierRank[cur] ?? 0)) planByUser.set(s.userId, s.tier);
    }

    // Sealed-wills headline + a 7-day delta for the admin stat tile.
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const [sealedWills, sealedWillsWeek] = await Promise.all([
      this.prisma.will.count({ where: { status: 'SEALED' } }),
      this.prisma.will.count({ where: { status: 'SEALED', sealedAt: { gte: weekAgo } } }),
    ]);

    return {
      total: users.length,
      users: users.map((u) => ({ ...u, lastIp: ipByUser.get(u.id) ?? null, plan: planByUser.get(u.id) ?? null })),
      stats: {
        byRegion: tally((u) => u.region),
        byStatus: tally((u) => u.idVerificationStatus),
        byRole: tally((u) => u.role),
        sealedWills,
        sealedWillsWeek,
      },
    };
  }
}
