import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { FeatureGuard } from '../common/guards/feature.guard';
import { RequireFeature } from '../common/decorators/require-feature.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AiIntakeService } from './ai-intake.service';
import { IntakeMessageDto, SeededWillDto } from './dto/ai-intake.dto';

// Gated to the Premium+ "aiIntake" entitlement via FeatureGuard. Admins and
// comped demo accounts pass automatically (EntitlementsService bypass).
//
// Throttled per route as well. Every other sensitive controller in this codebase
// tightens the global 100/min — auth, portal, death claims, files — and this is the
// only endpoint that spends money on each call, so leaving it on the shared default
// made the most expensive route the loosest one.
@ApiTags('ai-intake')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, FeatureGuard)
@RequireFeature('aiIntake')
@Controller('ai-intake')
export class AiIntakeController {
  constructor(private aiIntake: AiIntakeService) {}

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('start')
  @ApiOperation({ summary: 'Open a conversation with Ameen.' })
  start(@CurrentUser() user: { userId: string; region: string }) {
    return this.aiIntake.startSession(user.userId, user.region);
  }

  // A person types a sentence at a time; 20/min is far above human pace and far below
  // what a loop could spend.
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @Post(':sessionId/message')
  @ApiOperation({ summary: 'Send one turn.' })
  continueConversation(
    @Param('sessionId') sessionId: string,
    @CurrentUser() user: { userId: string; region: string },
    @Body() body: IntakeMessageDto,
  ) {
    return this.aiIntake.continueSession(sessionId, user.userId, user.region, body.message);
  }

  @Get(':sessionId')
  @ApiOperation({ summary: 'Resume a conversation.' })
  getSession(@Param('sessionId') sessionId: string, @CurrentUser() user: { userId: string }) {
    return this.aiIntake.getSession(sessionId, user.userId);
  }

  /**
   * Hand the conversation to the guided form. Returns a SEED, and creates nothing —
   * the will is created by the form's own save, so the disclaimer, the madhhab and
   * every validator belong to the user's own journey through it.
   */
  @Post(':sessionId/finalize')
  @ApiOperation({ summary: 'Carry the captured family into the guided form. Creates no will.' })
  finalize(@Param('sessionId') sessionId: string, @CurrentUser() user: { userId: string }) {
    return this.aiIntake.finalize(sessionId, user.userId);
  }

  /** Called once the form has saved the seeded draft, so one intake cannot seed two. */
  @Post(':sessionId/seeded')
  @ApiOperation({ summary: 'Record which will this conversation became.' })
  seeded(
    @Param('sessionId') sessionId: string,
    @CurrentUser() user: { userId: string },
    @Body() body: SeededWillDto,
  ) {
    return this.aiIntake.markSeeded(sessionId, user.userId, body.willId);
  }
}
