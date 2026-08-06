/**
 * The seam for object storage (uploads).
 *
 * Uploads go DIRECTLY from the client to storage via a presigned PUT — the file
 * never streams through this API. The client receives a short-lived, tightly-scoped
 * URL that only permits PUTting one specific object with one specific content-type
 * up to a size cap. We store only our OWN object key, never a client-supplied URL,
 * which is what closes the SSRF/phishing hole in the death-certificate flow.
 *
 * Config-gated like the payment and identity seams: with no credentials the module
 * supplies UnconfiguredStorageProvider, which 503s rather than pretending to work.
 */
export interface PresignedUpload {
  /** The URL the client PUTs the bytes to. Short-lived. */
  uploadUrl: string;
  /** The object key we persist and later resolve to a download URL. */
  key: string;
  /** Headers the client MUST send on the PUT for the signature to match. */
  requiredHeaders: Record<string, string>;
  /** Seconds until uploadUrl expires. */
  expiresInSeconds: number;
}

/** One stored object, as returned when listing under a prefix. */
export interface StoredObject {
  key: string;
  lastModified: Date;
  sizeBytes: number;
}

/**
 * Evidence that a compliance erasure actually happened. Returned by the erase
 * methods and recorded verbatim in the DataPurgeLog tombstone, because "we deleted
 * it" is a claim we make to bereaved families and regulators — it should be backed
 * by counts and a verification, not by the absence of an exception.
 */
export interface ErasureResult {
  /**
   * Which path ran. 'versions' — listed and deleted every version + delete marker
   * (AWS/MinIO). 'flat' — the store has no versioning API at all (Cloudflare R2), so a
   * plain delete IS permanent there. 'none' — no storage configured, nothing to erase.
   */
  method: 'versions' | 'flat' | 'none';
  /** Distinct object keys removed. */
  objectsDeleted: number;
  versionsDeleted: number;
  deleteMarkersDeleted: number;
  /** True only when a RE-LIST after deleting showed nothing left. */
  verifiedEmpty: boolean;
}

export interface StorageProviderPort {
  readonly name: string;
  readonly configured: boolean;

  /**
   * Issues a presigned PUT for one object. The caller has already validated the
   * content-type against an allow-list and chosen a namespaced key prefix.
   *
   * `contentLength` is the EXACT declared size, and it is signed: a PUT whose body
   * differs in length fails the signature, so a presign for a 2 MB document cannot
   * be spent on a 5 GB upload. (S3 has no "maximum length" condition on SigV4
   * presigns — exactness is the only enforceable shape, which is fine because the
   * client knows the byte count before it asks.) `maxBytes` is the per-kind cap,
   * echoed back for UI copy only.
   */
  presignUpload(params: {
    key: string;
    contentType: string;
    contentLength: number;
    maxBytes: number;
  }): Promise<PresignedUpload>;

  /**
   * A short-lived GET url for an object we own. `safeHeaders` PINS the response
   * Content-Type and Content-Disposition regardless of what bytes/metadata the
   * object actually holds — so a file whose bytes are HTML can never be served
   * as `text/html` and executed in the app origin. Always pass it for anything
   * a user uploaded.
   */
  presignDownload(
    key: string,
    safeHeaders?: { contentType?: string; disposition?: 'inline' | 'attachment'; filename?: string },
    expiresInSeconds?: number,
  ): Promise<string>;

  /** Lists objects under a key prefix (for the orphan reaper). */
  listObjects(prefix: string): Promise<StoredObject[]>;

  /**
   * Deletes the CURRENT version of one object (idempotent).
   *
   * NOT erasure. On a versioning-enabled bucket this only writes a delete marker —
   * AWS: "a simple DELETE cannot permanently delete an object" — so every prior
   * version stays readable by version id until lifecycle expiry. That is deliberate
   * here: versioning is the recovery net for the orphan reaper, which computes what
   * to delete by DIFFING storage against the database, and whose bugs would otherwise
   * be unrecoverable. For actual erasure use deleteAllVersions/purgePrefix.
   */
  deleteObject(key: string): Promise<void>;

  /**
   * PERMANENTLY erases one key: every version and delete marker, by version id.
   * Irreversible — there is no recovery after this.
   */
  deleteAllVersions(key: string): Promise<ErasureResult>;

  /**
   * PERMANENTLY erases everything under a key prefix, then VERIFIES by re-listing
   * that nothing remains. Irreversible.
   *
   * Prefix rather than a list of known keys, because an upload that was presigned and
   * PUT but never confirmed has no database row and is exactly as sensitive (an id
   * document, a death certificate) as one that has.
   */
  purgePrefix(prefix: string): Promise<ErasureResult>;
}

export const STORAGE_PROVIDER = Symbol('STORAGE_PROVIDER');
