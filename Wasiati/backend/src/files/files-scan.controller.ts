import { BadRequestException, Body, Controller, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsString } from 'class-validator';
import { createHmac, timingSafeEqual } from 'crypto';
import { FilesService } from './files.service';

export class ScanCallbackDto {
  /** The storage object key the scanner examined. */
  @IsString()
  key: string;

  /** Verdict from the malware scanner. */
  @IsIn(['CLEAN', 'INFECTED'])
  status: 'CLEAN' | 'INFECTED';
}

/**
 * Ingest point for the out-of-band malware scanner (AWS GuardDuty Malware Protection
 * for S3 → EventBridge → this webhook). Deliberately OUTSIDE the JWT-guarded
 * FilesController: the caller is infrastructure, not a user. It is authenticated by an
 * HMAC-SHA256 over the JSON body keyed with FILES_SCAN_WEBHOOK_SECRET — a forged or
 * unsigned call is rejected, so nobody can mark their own malware CLEAN. If the secret
 * is unset the endpoint refuses every call (fail-closed).
 */
@ApiTags('files')
@Controller('files')
export class FilesScanController {
  constructor(
    private files: FilesService,
    private config: ConfigService,
  ) {}

  @Post('scan-callback')
  @ApiOperation({ summary: 'Malware-scan verdict webhook (HMAC-signed; called by the scanner, not users).' })
  async scanCallback(@Body() dto: ScanCallbackDto, @Headers('x-scan-signature') signature?: string) {
    const secret = this.config.get<string>('FILES_SCAN_WEBHOOK_SECRET');
    if (!secret) throw new UnauthorizedException('Scan webhook is not configured.');
    if (!signature) throw new UnauthorizedException('Missing signature.');

    const expected = createHmac('sha256', secret).update(JSON.stringify({ key: dto.key, status: dto.status })).digest('hex');
    const a = Buffer.from(signature);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new UnauthorizedException('Invalid signature.');
    }
    if (!dto.key) throw new BadRequestException('Missing key.');

    return this.files.applyScanResult(dto.key, dto.status === 'CLEAN');
  }
}
