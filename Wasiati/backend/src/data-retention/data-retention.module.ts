import { Module } from '@nestjs/common';
import { DataRetentionService } from './data-retention.service';
import { DataRetentionController } from './data-retention.controller';
import { FilesModule } from '../files/files.module';
import { IdentityModule } from '../identity/identity.module';

// FilesModule supplies STORAGE_PROVIDER: the purge must erase the deceased's stored
// objects through the same region-pinned adapter that stored them. IdentityModule
// supplies the KYC vendor, which holds the ID scan and selfie that never reach our bucket.
@Module({
  imports: [FilesModule, IdentityModule],
  controllers: [DataRetentionController],
  providers: [DataRetentionService],
  exports: [DataRetentionService],
})
export class DataRetentionModule {}
