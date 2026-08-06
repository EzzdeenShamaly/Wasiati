import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { Region } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { FeatureGuard } from '../common/guards/feature.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { RequireFeature } from '../common/decorators/require-feature.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { BurialEstimatesService } from './burial-estimates.service';
import { CreateBurialEstimateDto, SubmitManualQuoteDto } from './dto/burial-estimate.dto';

// Ultimate-tier feature (US/CA). FeatureGuard enforces the 'burialPlanning'
// entitlement; admins and comped demo accounts bypass automatically.
@ApiTags('burial-estimates')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, FeatureGuard)
@RequireFeature('burialPlanning')
@Controller('burial-estimates')
export class BurialEstimatesController {
  constructor(private burialEstimates: BurialEstimatesService) {}

  @Post()
  create(@CurrentUser() user: { userId: string; region: Region }, @Body() body: CreateBurialEstimateDto) {
    return this.burialEstimates.createEstimate(
      user.userId,
      user.region,
      body.city,
      body.baseAmount,
      body.currency,
      body.inflationRatePercent,
      body.projectionYears,
    );
  }

  @Get()
  list(@CurrentUser() user: { userId: string }) {
    return this.burialEstimates.listForUser(user.userId);
  }

  @Post(':estimateId/request-quote')
  requestQuote(@CurrentUser() user: { userId: string }, @Param('estimateId') estimateId: string) {
    return this.burialEstimates.requestRealQuote(estimateId, user.userId);
  }

  // Admin-only — submitting the manually-sourced mosque quote
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @Post(':estimateId/manual-quote')
  submitQuote(
    @Param('estimateId') estimateId: string,
    @CurrentUser() admin: { userId: string },
    @Body() body: SubmitManualQuoteDto,
  ) {
    return this.burialEstimates.submitManualQuote(estimateId, admin.userId, body.amount, body.notes);
  }
}
