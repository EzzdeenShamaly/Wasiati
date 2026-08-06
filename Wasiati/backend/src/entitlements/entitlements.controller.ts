import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { EntitlementsService } from './entitlements.service';

@ApiTags('entitlements')
@ApiBearerAuth()
@Controller('entitlements')
export class EntitlementsController {
  constructor(private entitlements: EntitlementsService) {}

  @UseGuards(JwtAuthGuard)
  @Get('me')
  @ApiOperation({ summary: "Resolve the current user's effective entitlement (tier + feature flags + source)." })
  me(@CurrentUser() user: { userId: string }) {
    return this.entitlements.resolve(user.userId);
  }
}
