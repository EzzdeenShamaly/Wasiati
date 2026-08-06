import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ErasureResult, PresignedUpload, StorageProviderPort } from '../storage-provider.interface';

/**
 * Placeholder storage adapter. With no bucket/credentials configured this FAILS
 * loudly (503) rather than no-op — an upload endpoint that silently succeeds but
 * stores nothing is worse than one that is honestly absent.
 *
 * Swap in S3StorageProvider by setting STORAGE_BUCKET (+ region/endpoint/keys).
 */
@Injectable()
export class UnconfiguredStorageProvider implements StorageProviderPort {
  readonly name = 'UNCONFIGURED';
  readonly configured = false;

  private fail(): never {
    throw new ServiceUnavailableException(
      'File uploads are not available yet. Our team is enabling secure storage — no action is needed from you.',
    );
  }

  presignUpload(): Promise<PresignedUpload> {
    this.fail();
  }

  presignDownload(
    _key?: string,
    _safeHeaders?: { contentType?: string; disposition?: 'inline' | 'attachment'; filename?: string },
    _expiresInSeconds?: number,
  ): Promise<string> {
    this.fail();
  }

  // The reaper calls these; with no storage there is nothing to list or delete.
  async listObjects(): Promise<never[]> {
    return [];
  }

  async deleteObject(): Promise<void> {
    return;
  }

  /**
   * No bucket means no bytes, so "nothing remains" is TRUE rather than a pretence —
   * with one caveat enforced by the caller, not here: the purge refuses to accept this
   * answer if the database still records files for that user, because that combination
   * means storage was misconfigured out from under real objects.
   */
  private nothingToErase(): ErasureResult {
    return { method: 'none', objectsDeleted: 0, versionsDeleted: 0, deleteMarkersDeleted: 0, verifiedEmpty: true };
  }

  async deleteAllVersions(): Promise<ErasureResult> {
    return this.nothingToErase();
  }

  async purgePrefix(): Promise<ErasureResult> {
    return this.nothingToErase();
  }
}
