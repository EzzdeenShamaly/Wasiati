import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { BurialEstimatesService } from './burial-estimates.service';

/**
 * Admin side of the manual mosque-outreach loop, mirroring the death-claims queue
 * (`/admin/death-claims/pending`). Deliberately NOT behind FeatureGuard: answering
 * the queue is admin work, not use of the burialPlanning entitlement.
 *
 * Answering a request stays where it always was —
 * `POST /burial-estimates/:id/manual-quote` (RolesGuard'd inside the user-facing
 * controller); this controller only adds the missing way to FIND them.
 */
@ApiTags('burial-estimates')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/burial-estimates')
export class BurialEstimatesAdminController {
  constructor(private burialEstimates: BurialEstimatesService) {}

  @Get('pending')
  @ApiOperation({ summary: 'Quote requests awaiting a manually-sourced answer, plus recently answered ones.' })
  listPending() {
    return this.burialEstimates.listQuoteQueue();
  }
}
