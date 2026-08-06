import { Body, Controller, Get, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CheckinFrequency, ClaimInitPolicy } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { CheckinService } from './checkin.service';

export class UpdateCheckinDto {
  @IsOptional()
  @IsBoolean()
  checkinEnabled?: boolean;

  @IsOptional()
  @IsEnum(CheckinFrequency)
  checkinFrequency?: CheckinFrequency;
}

export class SetClaimPolicyDto {
  @IsEnum(ClaimInitPolicy)
  claimInitPolicy: ClaimInitPolicy;
}

@ApiTags('checkin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('checkin')
export class CheckinController {
  constructor(private checkin: CheckinService) {}

  @Get()
  @ApiOperation({ summary: 'My inactivity check-in settings and state.' })
  status(@CurrentUser() user: { userId: string }) {
    return this.checkin.status(user.userId);
  }

  @Put()
  @ApiOperation({ summary: 'Turn the check-in on/off and set its frequency. Off by default.' })
  update(@CurrentUser() user: { userId: string }, @Body() dto: UpdateCheckinDto) {
    return this.checkin.updateSettings(user.userId, dto);
  }

  @Put('claim-policy')
  @ApiOperation({ summary: 'Who may report my death: trustee only, heirs with documents, or both.' })
  setClaimPolicy(@CurrentUser() user: { userId: string }, @Body() dto: SetClaimPolicyDto) {
    return this.checkin.setClaimInitPolicy(user.userId, dto.claimInitPolicy);
  }

  @Post('confirm')
  @ApiOperation({ summary: 'I am still here — resets reminders and any trustee alert.' })
  confirm(@CurrentUser() user: { userId: string }) {
    return this.checkin.confirmAlive(user.userId);
  }
}
