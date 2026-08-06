import { Body, Controller, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { WitnessesService } from './witnesses.service';
import { AddWitnessDto, ConfirmWitnessDto } from './dto/witness.dto';

@ApiTags('witnesses')
@Controller()
export class WitnessesController {
  constructor(private witnesses: WitnessesService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('wills/:willId/witnesses')
  add(@CurrentUser() user: { userId: string }, @Param('willId') willId: string, @Body() body: AddWitnessDto) {
    return this.witnesses.addWitness(willId, user.userId, body.fullName, body.phone, body.email);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('wills/:willId/witnesses')
  list(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.witnesses.listForWill(willId, user.userId);
  }

  // Public — the witness themselves isn't necessarily a logged-in platform user.
  @Throttle({ default: { limit: 3, ttl: 60000 } })
  @Post('witnesses/:witnessId/send-code')
  sendCode(@Param('witnessId') witnessId: string) {
    return this.witnesses.sendSigningCode(witnessId);
  }

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @Post('witnesses/:witnessId/confirm')
  confirm(@Param('witnessId') witnessId: string, @Body() body: ConfirmWitnessDto, @Req() req: any) {
    return this.witnesses.confirmSignature(
      witnessId,
      body.code,
      body.signatureData,
      body.legalName,
      req.ip,
      req.headers['user-agent'],
    );
  }
}
