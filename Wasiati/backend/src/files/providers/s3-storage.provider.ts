import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  ListObjectVersionsCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { ErasureResult, PresignedUpload, StorageProviderPort, StoredObject } from '../storage-provider.interface';

/** S3 caps a single DeleteObjects call at 1000 entries. */
const DELETE_BATCH = 1000;

/**
 * S3-compatible object storage. Works against AWS S3, Cloudflare R2, or MinIO in dev
 * (STORAGE_ENDPOINT + STORAGE_FORCE_PATH_STYLE=true).
 *
 * Region residency: each regional deployment points at its OWN bucket, so a KSA
 * user's documents live in the KSA bucket. That is a deployment concern (one
 * STORAGE_BUCKET per region), not something this class chooses.
 */
@Injectable()
export class S3StorageProvider implements StorageProviderPort {
  readonly name = 'S3';
  private readonly logger = new Logger(S3StorageProvider.name);
  private client?: S3Client;

  constructor(private config: ConfigService) {}

  private get bucket(): string | undefined {
    return this.config.get<string>('STORAGE_BUCKET');
  }

  get configured(): boolean {
    // AWS creds may come from the ambient environment (IAM role), so only a bucket
    // is strictly required here; the SDK resolves credentials at call time.
    return !!this.bucket;
  }

  private s3(): S3Client {
    if (this.client) return this.client;
    const region = this.config.get<string>('STORAGE_REGION') ?? 'us-east-1';
    const endpoint = this.config.get<string>('STORAGE_ENDPOINT') || undefined;
    const forcePathStyle = this.config.get<string>('STORAGE_FORCE_PATH_STYLE') === 'true';
    const accessKeyId = this.config.get<string>('STORAGE_ACCESS_KEY_ID');
    const secretAccessKey = this.config.get<string>('STORAGE_SECRET_ACCESS_KEY');
    this.client = new S3Client({
      region,
      endpoint,
      forcePathStyle,
      // Explicit keys for MinIO/R2; omitted → SDK uses the ambient IAM role on AWS.
      credentials: accessKeyId && secretAccessKey ? { accessKeyId, secretAccessKey } : undefined,
      // AWS SDK v3 (>= 3.729) defaults data-integrity checksums ON for PutObject. For a
      // PRESIGNED PUT that makes the signed URL demand x-amz-sdk-checksum-algorithm /
      // x-amz-checksum-* headers the browser/Dart client never sends, so REAL S3 rejects
      // the upload (403) — while MinIO tolerates it, hiding the break in dev. WHEN_REQUIRED
      // restores the pre-3.729 behaviour (checksum only when the op truly needs it), which
      // is AWS's documented fix for presigned PutObject. Verify against real S3 at cutover.
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
    });
    return this.client;
  }

  async presignUpload(params: {
    key: string;
    contentType: string;
    contentLength: number;
    maxBytes: number;
  }): Promise<PresignedUpload> {
    const expiresInSeconds = 300;
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: params.key,
      ContentType: params.contentType,
      // The DECLARED size, bound into the signature. The old code claimed this and
      // passed undefined — so a valid presign accepted a body of ANY size, and the
      // 15 MB / 500 MB caps were client-side courtesy plus a confirm-time re-check,
      // with the oversized bytes already stored (and billed) until the reaper swept
      // them. Signed, a mismatched Content-Length fails the PUT at S3's door.
      ContentLength: params.contentLength,
    });
    const uploadUrl = await getSignedUrl(this.s3(), command, {
      expiresIn: expiresInSeconds,
      // The client must echo these exact headers or the signature won't match.
      signableHeaders: new Set(['content-type', 'content-length']),
    });

    return {
      uploadUrl,
      key: params.key,
      requiredHeaders: {
        'Content-Type': params.contentType,
        'Content-Length': String(params.contentLength),
      },
      expiresInSeconds,
    };
  }

  async presignDownload(
    key: string,
    safeHeaders?: { contentType?: string; disposition?: 'inline' | 'attachment'; filename?: string },
    expiresInSeconds = 300,
  ): Promise<string> {
    // Pin the RESPONSE Content-Type and Content-Disposition on the presigned GET.
    // These override whatever type/metadata the stored object carries, so a file
    // whose bytes are HTML/JS is served as (say) application/octet-stream with an
    // attachment disposition and can never execute in the browser. Defaults are
    // the paranoid choice: opaque binary + forced download.
    const filename = safeHeaders?.filename?.replace(/[^\w.-]/g, '_') ?? 'download';
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ResponseContentType: safeHeaders?.contentType ?? 'application/octet-stream',
      ResponseContentDisposition: `${safeHeaders?.disposition ?? 'attachment'}; filename="${filename}"`,
    });
    return getSignedUrl(this.s3(), command, { expiresIn: expiresInSeconds });
  }

  async listObjects(prefix: string): Promise<StoredObject[]> {
    const out: StoredObject[] = [];
    let token: string | undefined;
    do {
      const res = await this.s3().send(
        new ListObjectsV2Command({ Bucket: this.bucket, Prefix: prefix, ContinuationToken: token }),
      );
      for (const o of res.Contents ?? []) {
        if (o.Key) out.push({ key: o.Key, lastModified: o.LastModified ?? new Date(0), sizeBytes: o.Size ?? 0 });
      }
      token = res.IsTruncated ? res.NextContinuationToken : undefined;
    } while (token);
    return out;
  }

  async deleteObject(key: string): Promise<void> {
    await this.s3().send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }

  // --- compliance erasure ----------------------------------------------------
  //
  // Everything below exists because deleteObject() above does NOT erase on a
  // versioned bucket. AWS: "a simple DELETE cannot permanently delete an object...
  // Amazon S3 inserts a delete marker" and "To delete versioned objects permanently,
  // you must use DELETE Object versionId." A purge that claims permanent erasure has
  // to name every version.

  async deleteAllVersions(key: string): Promise<ErasureResult> {
    // Listing is prefix-based, so filter to the EXACT key — erasing "a/b.pdf" must not
    // take "a/b.pdf.bak" with it.
    return this.erase(key, (k) => k === key);
  }

  async purgePrefix(prefix: string): Promise<ErasureResult> {
    return this.erase(prefix, () => true);
  }

  private async erase(prefix: string, keep: (key: string) => boolean): Promise<ErasureResult> {
    try {
      const counts = await this.eraseVersions(prefix, keep);
      const remaining = await this.remainingVersions(prefix, keep);
      return { method: 'versions', ...counts, verifiedEmpty: remaining === 0 };
    } catch (err) {
      if (!S3StorageProvider.lacksVersioningApi(err)) throw err;
      // Cloudflare R2 has no versioning at all and returns NotImplemented for the
      // versions API. There, a plain delete IS permanent, so this stays honest.
      const counts = await this.eraseFlat(prefix, keep);
      const left = (await this.listObjects(prefix)).filter((o) => keep(o.key)).length;
      return { method: 'flat', ...counts, verifiedEmpty: left === 0 };
    }
  }

  /** Deletes every version AND delete marker under the prefix, paging through all of them. */
  private async eraseVersions(prefix: string, keep: (key: string) => boolean) {
    const keys = new Set<string>();
    let versionsDeleted = 0;
    let deleteMarkersDeleted = 0;
    let KeyMarker: string | undefined;
    let VersionIdMarker: string | undefined;

    do {
      const page = await this.s3().send(
        new ListObjectVersionsCommand({ Bucket: this.bucket, Prefix: prefix, KeyMarker, VersionIdMarker }),
      );
      const doomed: { Key: string; VersionId: string }[] = [];
      // Delete markers are returned in their own array and are themselves versions —
      // leaving them behind means the "is it empty?" check never passes.
      for (const v of page.Versions ?? []) {
        if (!v.Key || !v.VersionId || !keep(v.Key)) continue;
        doomed.push({ Key: v.Key, VersionId: v.VersionId });
        keys.add(v.Key);
        versionsDeleted++;
      }
      for (const m of page.DeleteMarkers ?? []) {
        if (!m.Key || !m.VersionId || !keep(m.Key)) continue;
        doomed.push({ Key: m.Key, VersionId: m.VersionId });
        keys.add(m.Key);
        deleteMarkersDeleted++;
      }
      for (let i = 0; i < doomed.length; i += DELETE_BATCH) {
        await this.deleteBatch(doomed.slice(i, i + DELETE_BATCH));
      }
      KeyMarker = page.IsTruncated ? page.NextKeyMarker : undefined;
      VersionIdMarker = page.IsTruncated ? page.NextVersionIdMarker : undefined;
    } while (KeyMarker || VersionIdMarker);

    return { objectsDeleted: keys.size, versionsDeleted, deleteMarkersDeleted };
  }

  /** For stores with no versioning API (R2): delete the objects themselves. */
  private async eraseFlat(prefix: string, keep: (key: string) => boolean) {
    const objects = (await this.listObjects(prefix)).filter((o) => keep(o.key));
    for (let i = 0; i < objects.length; i += DELETE_BATCH) {
      await this.deleteBatch(objects.slice(i, i + DELETE_BATCH).map((o) => ({ Key: o.key })));
    }
    return { objectsDeleted: objects.length, versionsDeleted: 0, deleteMarkersDeleted: 0 };
  }

  /**
   * DeleteObjects reports PER-OBJECT failures inside an HTTP 200 body and the SDK does
   * not throw on them — an Object Lock retention, a legal hold or a missing permission
   * comes back in `Errors`. Unread, the purge would report success over files it never
   * deleted, which is the exact lie the tombstone must not tell.
   */
  private async deleteBatch(objects: { Key: string; VersionId?: string }[]): Promise<void> {
    if (!objects.length) return;
    const res = await this.s3().send(
      new DeleteObjectsCommand({ Bucket: this.bucket, Delete: { Objects: objects, Quiet: true } }),
    );
    if (res.Errors?.length) {
      const first = res.Errors[0];
      throw new Error(
        `S3 refused ${res.Errors.length} deletion(s); first: ${first.Key} [${first.Code}] ${first.Message ?? ''}`,
      );
    }
  }

  /**
   * The verification. Deliberately ListObjectVersions and NOT ListObjectsV2: the v2
   * listing hides noncurrent versions and delete markers, so it would report "empty"
   * for a prefix whose every byte is still recoverable — a check that always passes.
   */
  private async remainingVersions(prefix: string, keep: (key: string) => boolean): Promise<number> {
    const page = await this.s3().send(new ListObjectVersionsCommand({ Bucket: this.bucket, Prefix: prefix }));
    const left = [...(page.Versions ?? []), ...(page.DeleteMarkers ?? [])];
    return left.filter((v) => v.Key && keep(v.Key)).length;
  }

  /** True when the store has no versioning API at all (Cloudflare R2 → NotImplemented). */
  private static lacksVersioningApi(err: unknown): boolean {
    const e = err as { name?: string; Code?: string; $metadata?: { httpStatusCode?: number } };
    return e?.name === 'NotImplemented' || e?.Code === 'NotImplemented' || e?.$metadata?.httpStatusCode === 501;
  }
}
