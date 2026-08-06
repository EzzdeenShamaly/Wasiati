import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsInt, IsString, Min } from 'class-validator';
import { Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { FilesService } from './files.service';

export class PresignUploadDto {
  @IsIn(['death_certificate', 'id_document', 'video_legacy'])
  kind: string;

  @IsString()
  contentType: string;

  // The client's declared byte size — quota is provisionally checked here and
  // re-checked against the real size at /confirm.
  @IsInt()
  @Min(1)
  sizeBytes: number;
}

export class ConfirmUploadDto {
  @IsIn(['death_certificate', 'id_document', 'video_legacy'])
  kind: string;

  @IsString()
  key: string;

  @IsString()
  contentType: string;

  @IsInt()
  @Min(1)
  sizeBytes: number;
}

@ApiTags('files')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('files')
export class FilesController {
  constructor(private files: FilesService) {}

  @Get('quota')
  @ApiOperation({ summary: 'My storage usage vs the 1 GB per-user quota.' })
  quota(@CurrentUser() user: { userId: string }) {
    return this.files.quota(user.userId);
  }

  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @Post('presign')
  @ApiOperation({
    summary: 'Presign a direct-to-storage upload. Owner-scoped key + type/size/quota checks; 503 until storage is configured.',
  })
  presign(@CurrentUser() user: { userId: string }, @Body() dto: PresignUploadDto) {
    return this.files.presignUpload(user.userId, dto.kind, dto.contentType, dto.sizeBytes);
  }

  @Post('confirm')
  @ApiOperation({ summary: 'Record an object after the client PUT; re-checks the quota against the real size.' })
  confirm(@CurrentUser() user: { userId: string }, @Body() dto: ConfirmUploadDto) {
    return this.files.confirmUpload(user.userId, dto.kind, dto.key, dto.contentType, dto.sizeBytes);
  }

  // Declared before GET :kind so the two-segment download path is unambiguous.
  @Get(':id/download')
  @ApiOperation({
    summary: 'A short-lived download URL for one of MY files. Refused unless the file passed the malware scan.',
  })
  download(@CurrentUser() user: { userId: string }, @Param('id') id: string) {
    return this.files.presignDownloadOwned(user.userId, id);
  }

  @Get(':kind')
  @ApiOperation({ summary: "My files of a kind (e.g. 'video_legacy')." })
  list(@CurrentUser() user: { userId: string }, @Param('kind') kind: string) {
    return this.files.listForUser(user.userId, kind);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete one of my files, freeing quota.' })
  remove(@CurrentUser() user: { userId: string }, @Param('id') id: string) {
    return this.files.deleteOwned(user.userId, id);
  }
}
