import { Body, Controller, Delete, Get, Param, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ContentService } from './content.service';

export class UpsertContentDto {
  @IsString()
  @MinLength(1)
  @MaxLength(5000)
  en: string;

  @IsString()
  @MinLength(1)
  @MaxLength(5000)
  ar: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;

  @IsOptional()
  @IsBoolean()
  published?: boolean;
}

@ApiTags('content')
@Controller('content')
export class ContentController {
  constructor(private content: ContentService) {}

  /**
   * PUBLIC. The published string overrides the app merges over its bundled ARB at
   * launch. No auth: these are the same strings shown in the UI, and the app needs
   * them before sign-in (welcome, login copy).
   */
  @Get()
  @ApiOperation({ summary: 'Published content overrides as { key: { en, ar } }.' })
  overrides() {
    return this.content.publishedOverrides();
  }

  // --- admin ---
  @Get('admin')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Every content string, published or draft, with its last editor.' })
  listAll() {
    return this.content.listAll();
  }

  @Get('admin/:key/revisions')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Audit trail for one content string, newest first.' })
  revisions(@Param('key') key: string) {
    return this.content.revisions(key);
  }

  @Put('admin/:key')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Publish/update a string (EN + AR). Writes an audit revision.' })
  upsert(@CurrentUser() user: { userId: string }, @Param('key') key: string, @Body() dto: UpsertContentDto) {
    return this.content.upsert(key, dto, user.userId);
  }

  @Delete('admin/:key')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Remove an override so the app reverts to the bundled string.' })
  remove(@CurrentUser() user: { userId: string }, @Param('key') key: string) {
    return this.content.remove(key, user.userId);
  }
}
