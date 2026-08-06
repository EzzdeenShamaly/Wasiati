import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { DataRetentionService } from './data-retention.service';

// Admin-only operational controls for the posthumous purge. The purge normally runs
// automatically on a daily schedule; these let an admin force it or purge one account.
@ApiTags('data-retention')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/data-retention')
export class DataRetentionController {
  constructor(private retention: DataRetentionService) {}

  @Post('run')
  @ApiOperation({ summary: 'Run the posthumous-purge sweep now (all accounts past their retention window).' })
  run() {
    return this.retention.runDailyPurge();
  }

  @Post('purge/:userId')
  @ApiOperation({ summary: 'Immediately purge ALL data for one deceased account (irreversible).' })
  purge(@Param('userId') userId: string) {
    return this.retention.purgeUser(userId);
  }

  @Post('reconcile')
  @ApiOperation({
    summary: 'Check whether promised purges actually happened. Read-only; returns overdue accounts.',
  })
  reconcile() {
    return this.retention.reconcile();
  }

  @Post('remind')
  @ApiOperation({ summary: 'Send any due 30/7/3-day retention reminders now.' })
  remind() {
    return this.retention.sendDueReminders();
  }

  @Post('schedule/:userId')
  @ApiOperation({ summary: 'Ops: set a purge date N days out (resets reminder tracking).' })
  schedule(@Param('userId') userId: string, @Body() body: { days: number }) {
    return this.retention.schedulePurge(userId, body.days);
  }

  // Legal hold. A contested will or any preservation obligation must be able to stop the
  // purge — otherwise the product destroys the disputed instrument on schedule.
  @Post('legal-hold/:userId')
  @ApiOperation({ summary: 'Suspend the purge for one estate indefinitely (litigation / preservation).' })
  hold(
    @CurrentUser() actor: { userId: string },
    @Param('userId') userId: string,
    @Body() body: { reason: string },
  ) {
    return this.retention.placeLegalHold(userId, actor.userId, body?.reason);
  }

  @Post('legal-hold/:userId/release')
  @ApiOperation({ summary: 'Lift a legal hold, re-arming the normal retention schedule.' })
  releaseHold(@CurrentUser() actor: { userId: string }, @Param('userId') userId: string) {
    return this.retention.releaseLegalHold(userId, actor.userId);
  }
}
