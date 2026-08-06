import { Module } from '@nestjs/common';
import { DeathClaimsService } from './death-claims.service';
import { DeathClaimsController } from './death-claims.controller';
import { ClaimUploadsController } from './claim-uploads.controller';
// One guard class for every claim-token route — the claim-submit route uses it too. A
// second copy would mean two classes with one name, two hashes and one metadata key.
import { ClaimTokenGuard } from './claim-token.guard';
import { AuthModule } from '../auth/auth.module';
import { DataRetentionModule } from '../data-retention/data-retention.module';
// For the accountless death-certificate upload: ClaimUploadsController delegates into the
// exported FilesService rather than duplicating any of its checks.
import { FilesModule } from '../files/files.module';

@Module({
  imports: [AuthModule, DataRetentionModule, FilesModule],
  controllers: [DeathClaimsController, ClaimUploadsController],
  providers: [DeathClaimsService, ClaimTokenGuard],
  exports: [DeathClaimsService],
})
export class DeathClaimsModule {}
