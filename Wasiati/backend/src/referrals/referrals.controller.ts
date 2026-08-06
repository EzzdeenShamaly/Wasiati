import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ReferralsService } from './referrals.service';

export class ClaimReferralDto {
  @IsString()
  @Length(4, 32)
  code: string;
}

@ApiTags('referrals')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('referrals')
export class ReferralsController {
  constructor(private referrals: ReferralsService) {}

  @Get('me')
  @ApiOperation({ summary: 'My referral code, share link and reward totals.' })
  me(@CurrentUser() user: { userId: string }) {
    return this.referrals.summary(user.userId);
  }

  @Post('claim')
  @ApiOperation({ summary: "Apply someone's referral code — before your first purchase." })
  claim(@CurrentUser() user: { userId: string }, @Body() dto: ClaimReferralDto) {
    return this.referrals.claim(user.userId, dto.code);
  }
}
