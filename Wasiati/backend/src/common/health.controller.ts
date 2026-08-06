import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { PrismaService } from '../prisma/prisma.service';
import { deploymentRegion } from './geo.util';

/**
 * The ALB health check target. Public and unauthenticated by design — a health
 * check that needs a token is a health check that fails closed on an auth bug.
 *
 * `SELECT 1` is the point: a container whose process is up but whose database is
 * unreachable must report unhealthy, or the load balancer keeps routing traffic
 * to an instance that can only serve errors. Region is included so a
 * misconfigured deployment is visible from a curl, not just from the boot log.
 */
@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private prisma: PrismaService) {}

  @Get()
  @ApiOperation({ summary: 'Liveness + database reachability. Used by the load balancer.' })
  async check() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      // 503, not 500: "unhealthy, stop routing to me" — the ALB treats any
      // non-2xx as failing, and 503 says why without leaking internals.
      throw new ServiceUnavailableException('Database unreachable.');
    }
    return { status: 'ok', region: deploymentRegion() };
  }
}
