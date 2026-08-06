import { Body, Controller, Delete, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { EntitlementsService } from './entitlements.service';
import { GrantCompDto } from './dto/comp.dto';

/**
 * Admin-only comp management. Lets an admin hand any account full (or tiered)
 * access without payment — e.g. investor demos, QA/test accounts, support.
 * ADMIN is derived from the JWT (RolesGuard), never trusted from the body.
 */
@ApiTags('admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/users')
export class EntitlementsAdminController {
  constructor(private entitlements: EntitlementsService) {}

  @Post(':id/comp')
  @ApiOperation({ summary: 'Grant a comped tier to a user (demo/testing, no payment).' })
  grant(@Param('id') id: string, @Body() dto: GrantCompDto, @CurrentUser() admin: { userId: string }) {
    return this.entitlements.grantComp(id, dto.tier, admin.userId, dto.expiresAt ? new Date(dto.expiresAt) : undefined);
  }

  @Delete(':id/comp')
  @ApiOperation({ summary: 'Revoke a user comp grant.' })
  revoke(@Param('id') id: string) {
    return this.entitlements.revokeComp(id);
  }
}
