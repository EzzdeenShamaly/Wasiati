import { Global, Module } from '@nestjs/common';
import { EntitlementsService } from './entitlements.service';
import { EntitlementsController } from './entitlements.controller';
import { EntitlementsAdminController } from './entitlements-admin.controller';
import { FeatureGuard } from '../common/guards/feature.guard';

// Global so FeatureGuard / EntitlementsService can gate endpoints in any module.
@Global()
@Module({
  controllers: [EntitlementsController, EntitlementsAdminController],
  providers: [EntitlementsService, FeatureGuard],
  exports: [EntitlementsService, FeatureGuard],
})
export class EntitlementsModule {}
