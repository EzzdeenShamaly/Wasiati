import { BadRequestException, Body, Controller, NotFoundException, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { SubscriptionTier } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * DEV ONLY — grants a comp tier to a throwaway account, so an end-to-end run can reach
 * the parts of the product that are behind the paywall.
 *
 * This exists because sealing a will now REQUIRES an active plan, enforced server-side
 * (docs/DECISIONS.md §25). That is correct — it is the revenue model, and it deserves a
 * server guarantee rather than UI routing. But it also means an e2e run that registers a
 * fresh account can no longer produce a SEALED will, and a sealed will is the precondition
 * for the entire death-claim and heir-portal half of the product. The alternative was for
 * those tests to drive a real Stripe checkout, which needs live keys and a webhook the
 * suite cannot receive.
 *
 * Granting a comp is exactly what an admin already does through /admin — this is the same
 * operation without needing admin credentials the suite has no way to know.
 *
 * Never reachable in production: DevModule is only imported when NODE_ENV !== production
 * AND OTP_DEV_ECHO=true, and env.validation refuses that flag in production — so the route
 * is ABSENT, not merely guarded. Same seam that already hands out live OTP codes, which
 * are considerably more sensitive than a free plan on a test account.
 */
@ApiTags('dev')
@Controller('dev')
export class DevEntitlementController {
  constructor(private prisma: PrismaService) {}

  @Post('comp')
  async grantComp(@Body() body: { email?: string; tier?: string }) {
    const email = (body?.email ?? '').trim().toLowerCase();
    if (!email) throw new BadRequestException('email is required.');

    const tier = (body?.tier ?? 'ULTIMATE').toUpperCase();
    if (!(tier in SubscriptionTier)) {
      throw new BadRequestException(`Unknown tier "${tier}". One of: ${Object.keys(SubscriptionTier).join(', ')}.`);
    }

    const { count } = await this.prisma.user.updateMany({
      where: { email },
      data: { compTier: tier as SubscriptionTier, compExpiresAt: null, compGrantedBy: 'dev' },
    });
    if (count === 0) throw new NotFoundException('No user with that email.');
    return { email, compTier: tier };
  }
}
