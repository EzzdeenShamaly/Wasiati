import { Body, Controller, Get, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ZakatService } from './zakat.service';

export class SetHawlDto {
  /** Hijri day of the month. */
  @IsInt()
  @Min(1)
  @Max(30)
  day: number;

  /** Hijri month. */
  @IsInt()
  @Min(1)
  @Max(12)
  month: number;
}

export class SetCharityUrlDto {
  @IsOptional()
  @IsString()
  url?: string;
}

@ApiTags('zakat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('zakat')
export class ZakatController {
  constructor(private zakat: ZakatService) {}

  @Get('estimate')
  @ApiOperation({
    summary: 'Zakat estimate over my assets. GUIDANCE, NOT A RULING.',
    description:
      'Base is cash, bank, shares and gold only. Crypto is excluded and disclosed. ' +
      'Amounts that cannot be converted exactly are listed rather than guessed at. ' +
      '503 when no current gold price is configured for the user’s currency.',
  })
  estimate(@CurrentUser() user: { userId: string }) {
    return this.zakat.estimate(user.userId);
  }

  @Put('hawl')
  @ApiOperation({ summary: 'Set my ḥawl anniversary — Hijri day and month only.' })
  setHawl(@CurrentUser() user: { userId: string }, @Body() dto: SetHawlDto) {
    return this.zakat.setHawl(user.userId, dto.day, dto.month);
  }

  @Post('admin/charity-url')
  @UseGuards(RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({
    summary: 'Publish (or clear) the charity link that gates the "Pay your zakah" button.',
  })
  setCharityUrl(@CurrentUser() user: { userId: string }, @Body() dto: SetCharityUrlDto) {
    return this.zakat.setCharityUrl(dto.url ?? null, user.userId);
  }
}
