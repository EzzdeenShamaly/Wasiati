import { Logger, Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { FilesController } from './files.controller';
import { FilesScanController } from './files-scan.controller';
import { FilesService } from './files.service';
import { FilesReaperService } from './files-reaper.service';
import { STORAGE_PROVIDER, StorageProviderPort } from './storage-provider.interface';
import { S3StorageProvider } from './providers/s3-storage.provider';
import { UnconfiguredStorageProvider } from './providers/unconfigured-storage.provider';

@Module({
  imports: [PrismaModule],
  controllers: [FilesController, FilesScanController],
  providers: [
    FilesService,
    FilesReaperService,
    S3StorageProvider,
    UnconfiguredStorageProvider,
    {
      provide: STORAGE_PROVIDER,
      inject: [S3StorageProvider, UnconfiguredStorageProvider],
      // S3-compatible storage when a bucket is configured; otherwise the adapter that
      // refuses with a 503 — never one that pretends an upload succeeded.
      useFactory: (s3: S3StorageProvider, unconfigured: UnconfiguredStorageProvider): StorageProviderPort => {
        if (s3.configured) {
          Logger.log('File storage: S3-compatible', 'FilesModule');
          return s3;
        }
        Logger.warn(
          'File storage: NOT CONFIGURED — /files/presign returns 503. Set STORAGE_BUCKET (+ region/keys).',
          'FilesModule',
        );
        return unconfigured;
      },
    },
  ],
  // STORAGE_PROVIDER is exported so the data-retention purge can erase a deceased
  // user's objects through the same region-pinned adapter the uploads used.
  exports: [FilesService, STORAGE_PROVIDER],
})
export class FilesModule {}
