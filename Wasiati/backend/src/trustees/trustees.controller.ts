import { Body, Controller, Get, Param, Post, UseGuards, Req } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { TrusteesService } from './trustees.service';
import { AddTrusteeDto, ConfirmTrusteeDto } from './dto/trustee.dto';

@ApiTags('trustees')
@Controller()
export class TrusteesController {
  constructor(private trustees: TrusteesService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('wills/:willId/trustees')
  add(@CurrentUser() user: { userId: string }, @Param('willId') willId: string, @Body() body: AddTrusteeDto) {
    return this.trustees.addTrustee(willId, user.userId, body.fullName, body.phone, body.email, body.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('wills/:willId/trustees')
  list(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.trustees.listForWill(willId, user.userId);
  }

  @Throttle({ default: { limit: 3, ttl: 60000 } })
  @Post('trustees/:trusteeId/send-code')
  sendCode(@Param('trusteeId') trusteeId: string) {
    return this.trustees.sendConfirmationCode(trusteeId);
  }

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @Post('trustees/:trusteeId/confirm')
  confirm(@Param('trusteeId') trusteeId: string, @Body() body: ConfirmTrusteeDto, @Req() req: any) {
    return this.trustees.confirm(trusteeId, body.code, req.ip, req.headers['user-agent']);
  }
}
