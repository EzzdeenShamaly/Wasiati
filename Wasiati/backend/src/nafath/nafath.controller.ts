import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { NafathService } from './nafath.service';

/**
 * KSA identity verification via Nafath. The client picks this rail for Saudi users
 * (US/CA use the document-KYC rail under /identity). Both feed the same
 * user.idVerificationStatus.
 */
@ApiTags('nafath')
@Controller('identity/nafath')
export class NafathController {
  constructor(private nafath: NafathService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('initiate')
  @ApiOperation({ summary: 'Start a Nafath MFA verification; returns the number to match in the app.' })
  initiate(@CurrentUser() user: { userId: string }, @Body() body: { nationalId: string }) {
    return this.nafath.initiate(user.userId, body.nationalId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('status')
  @ApiOperation({ summary: 'Poll a Nafath transaction the caller owns.' })
  status(@CurrentUser() user: { userId: string }, @Query('transId') transId: string) {
    return this.nafath.checkStatus(user.userId, transId);
  }

  // Public — Nafath posts the result here. Guarded by NAFATH_CALLBACK_SECRET.
  @Post('callback')
  @ApiOperation({ summary: 'Nafath result callback (server-to-server).' })
  callback(@Body() body: { transId?: string; status?: string; secret?: string }) {
    return this.nafath.handleCallback(body);
  }
}
