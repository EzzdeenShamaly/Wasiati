import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { MetricsService } from './metrics.service';

/**
 * Owner-only business insights. ADMIN role required (the owner) — no one else. The
 * `headline` field is written to be read aloud by a Siri Shortcut ("how is my
 * business doing"); the shortcut authenticates with the owner's token (stored in the
 * iOS Keychain, Face ID-gated) over TLS 1.3.
 */
@ApiTags('metrics')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/metrics')
export class MetricsController {
  constructor(private metrics: MetricsService) {}

  @Get('summary')
  @ApiOperation({ summary: 'Owner-only business KPIs + a spoken headline (Siri).' })
  summary() {
    return this.metrics.summary();
  }
}
