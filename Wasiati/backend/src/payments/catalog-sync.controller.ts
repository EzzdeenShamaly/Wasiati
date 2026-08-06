import { Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CatalogSyncService } from './catalog-sync.service';

/**
 * Admin: mirror the pricing catalogue into the payment provider.
 *
 * Routed under `/admin/commerce` alongside the rest of the catalogue admin, but it
 * LIVES in the payments module because it needs the provider port. Putting it in the
 * commerce module would close a cycle — payments already imports commerce for
 * PromotionsService.
 *
 * One way, by design: our catalogue is the source of truth and this pushes to the
 * provider so its dashboard can report by product. See CatalogSyncService.
 */
@ApiTags('admin-commerce')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/commerce')
export class CatalogSyncController {
  constructor(private catalogSync: CatalogSyncService) {}

  @Get('provider-catalog')
  @ApiOperation({ summary: 'How much of the catalogue is mirrored into the provider today.' })
  status() {
    return this.catalogSync.status();
  }

  @Post('provider-catalog/sync')
  @ApiOperation({ summary: 'Push every pricing plan into the payment provider. Idempotent.' })
  sync() {
    return this.catalogSync.sync();
  }
}
