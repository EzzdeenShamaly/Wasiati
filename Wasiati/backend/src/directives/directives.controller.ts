import { Body, Controller, Get, Param, ParseEnumPipe, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { DirectiveType } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { FeatureGuard } from '../common/guards/feature.guard';
import { RequireFeature } from '../common/decorators/require-feature.decorator';
import { DirectivesService } from './directives.service';
import { SaveDirectiveDto } from './dto/directive.dto';

@ApiTags('directives')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('directives')
export class DirectivesController {
  constructor(private directives: DirectivesService) {}

  // Reading is NOT feature-gated: the Wills page shows both cards to every tier
  // (the gate is a soft sell, spec §2), and a user whose Premium lapsed must still
  // see — and their family must still benefit from — a directive they signed.
  @Get()
  @ApiOperation({ summary: 'List my directive documents (POA / healthcare directive).' })
  list(@CurrentUser() user: { userId: string }) {
    return this.directives.list(user.userId);
  }

  @Put(':type')
  @UseGuards(FeatureGuard)
  @RequireFeature('directives')
  @ApiOperation({ summary: 'Save & sign a directive (upsert by type). Premium+ only.' })
  save(
    @CurrentUser() user: { userId: string },
    @Param('type', new ParseEnumPipe(DirectiveType)) type: DirectiveType,
    @Body() body: SaveDirectiveDto,
  ) {
    return this.directives.save(user.userId, type, body);
  }
}
