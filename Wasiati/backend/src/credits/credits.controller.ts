import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Region } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { REGION_CURRENCY } from '../common/geo.util';
import { CreditsService } from './credits.service';

@ApiTags('credits')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('credits')
export class CreditsController {
  constructor(private credits: CreditsService) {}

  @Get('me')
  @ApiOperation({
    summary: 'My account-credit balance (defaults to my region currency).',
    description:
      'balanceMinor is what can be spent today. heldMinor is earned referral commission still inside its 100-day hold.',
  })
  async me(@CurrentUser() user: { userId: string; region: Region }, @Query('currency') currency?: string) {
    const cur = (currency ?? REGION_CURRENCY[user.region] ?? 'USD').toUpperCase();
    const { spendableMinor, pendingMinor, totalMinor } = await this.credits.balances(user.userId, cur);
    return { currency: cur, balanceMinor: spendableMinor, heldMinor: pendingMinor, totalMinor };
  }

  @Get('history')
  @ApiOperation({ summary: 'My credit ledger — every grant and every spend.' })
  history(@CurrentUser() user: { userId: string }) {
    return this.credits.history(user.userId);
  }
}
