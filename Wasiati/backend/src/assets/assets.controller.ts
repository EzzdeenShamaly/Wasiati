import { Body, Controller, Delete, Get, Header, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { Region } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AssetsService } from './assets.service';
import { AddAssetDto } from './dto/add-asset.dto';
import { UpdateAssetDto } from './dto/update-asset.dto';

@ApiTags('assets')
@Controller()
export class AssetsController {
  constructor(private assets: AssetsService) {}

  // Public catalog lookup — the signup/will-creation form calls this to know
  // which local asset types to offer (e.g. RRSP only shown for CA users).
  @Get('assets/types/:region')
  getTypes(@Param('region') region: Region) {
    return this.assets.getAssetTypesForRegion(region);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('wills/:willId/assets')
  add(@CurrentUser() user: { userId: string }, @Param('willId') willId: string, @Body() body: AddAssetDto) {
    return this.assets.add(willId, user.userId, body);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('wills/:willId/assets')
  list(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.assets.listForWill(willId, user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Delete('assets/:assetId')
  remove(@CurrentUser() user: { userId: string }, @Param('assetId') assetId: string) {
    return this.assets.remove(assetId, user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Patch('assets/:assetId')
  update(@CurrentUser() user: { userId: string }, @Param('assetId') assetId: string, @Body() body: UpdateAssetDto) {
    return this.assets.update(assetId, user.userId, body);
  }

  // The prototype's "Export to Excel" — the inventory as a CSV Excel opens natively.
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('wills/:willId/assets/export.csv')
  @ApiOperation({ summary: "The will's asset & loan inventory as CSV." })
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @Header('Content-Disposition', 'attachment; filename="wasiati-inventory.csv"')
  exportCsv(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.assets.exportCsv(willId, user.userId);
  }
}
