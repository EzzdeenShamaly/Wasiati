import { BadRequestException, ForbiddenException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { EntitlementsService, Feature } from '../entitlements/entitlements.service';
import { STORAGE_PROVIDER, StorageProviderPort } from './storage-provider.interface';

/**
 * Upload orchestration. The bytes never pass through this API — the client PUTs
 * straight to storage with a presigned URL. This service decides WHAT may be
 * uploaded (content-type + size), WHERE (a key namespaced by owner + purpose), and
 * enforces a per-user storage QUOTA. So a user can only ever write objects under
 * their own prefix, of an allowed type, up to their quota.
 */

/**
 * Allowed upload kinds → content-type allow-list, per-file cap, key prefix, and the
 * entitlement an upload of that kind requires.
 *
 * `feature` is per-KIND rather than a guard on the controller, because the kinds are
 * not commercially alike: a death certificate is uploaded by a bereaved family and an
 * id_document by anyone verifying themselves — walling either behind a plan would break
 * a death claim and KYC. Only the legacy video is a sold feature.
 */
const UPLOAD_KINDS: Record<
  string,
  { contentTypes: string[]; maxBytes: number; prefix: string; feature?: Feature }
> = {
  death_certificate: {
    contentTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/heic'],
    maxBytes: 15 * 1024 * 1024,
    prefix: 'death-certificates',
  },
  id_document: {
    contentTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/heic'],
    maxBytes: 15 * 1024 * 1024,
    prefix: 'id-documents',
  },
  // A legacy video for the family (Premium+). Common web/mobile recording formats.
  video_legacy: {
    contentTypes: ['video/mp4', 'video/webm', 'video/quicktime'],
    // 750 MB. The recorder caps a take at ONE HOUR (owner, 29 Jul 2026), which at its
    // pinned 1.2 Mbps video + 96 kbps audio is ~582 MB. This ceiling has to sit above what
    // the recorder can actually produce, or a full-length take is recorded and then refused
    // at upload — worse than having no limit. The headroom covers bitrate variance, since
    // browsers treat the requested bitrate as a target rather than a guarantee.
    maxBytes: 750 * 1024 * 1024,
    prefix: 'legacy-videos',
    feature: 'videoMessages',
  },
};

const EXT: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
};

/** Total storage one user may hold across all their files (DECISIONS §0). */
export const USER_STORAGE_QUOTA_BYTES = 1024 * 1024 * 1024; // 1 GB

/** Every key prefix an upload can land under (used by the orphan reaper). */
export const UPLOAD_PREFIXES = Object.values(UPLOAD_KINDS).map((s) => s.prefix);

@Injectable()
export class FilesService {
  private readonly logger = new Logger(FilesService.name);

  constructor(
    @Inject(STORAGE_PROVIDER) private storage: StorageProviderPort,
    private prisma: PrismaService,
    private config: ConfigService,
    private entitlements: EntitlementsService,
  ) {}

  /**
   * Refuses an upload of a kind the user's plan does not include.
   *
   * Only WRITES are gated. Listing, downloading and deleting stay open on purpose: a
   * member whose Premium lapsed must still be able to reach — and remove — a video they
   * already recorded for their family. Locking someone out of their own legacy message
   * to sell them an upgrade is not a paywall we are willing to build.
   */
  private async assertMayUpload(ownerId: string, kind: string, spec: { feature?: Feature }) {
    await this.assertNotAwaitingPurge(ownerId);
    if (!spec.feature) return;
    if (await this.entitlements.hasFeature(ownerId, spec.feature)) return;
    throw new ForbiddenException('Video legacy messages are a Premium feature. Upgrade to record one.');
  }

  /**
   * An account already scheduled for posthumous purge accepts no new bytes.
   *
   * Without this the retention purge has a race it cannot win: a presigned PUT stays
   * spendable for its whole TTL, so an upload begun before the erasure sweep could land
   * in the bucket AFTER the sweep verified the prefix empty — leaving files behind a
   * tombstone that says they were destroyed. Refusing here means every URL that could
   * still land bytes was issued before release, i.e. expired ~90 days before the purge.
   * Reads and deletes stay open: the heirs' access period is the point of the window.
   */
  private async assertNotAwaitingPurge(ownerId: string) {
    const owner = await this.prisma.user.findUnique({
      where: { id: ownerId },
      select: { scheduledPurgeAt: true },
    });
    if (owner?.scheduledPurgeAt) {
      throw new ForbiddenException('This account is closed and can no longer accept uploads.');
    }
  }

  get available(): boolean {
    return this.storage.configured;
  }

  /**
   * When true, a fresh upload is quarantined (scanStatus PENDING) and refused by
   * presignDownload until an out-of-band scanner marks it CLEAN. Off in dev / when
   * no scanner is wired, so uploads confirm straight to CLEAN and stay downloadable.
   */
  private get malwareScanEnabled(): boolean {
    return this.config.get<string>('MALWARE_SCAN_ENABLED') === 'true';
  }

  private static prefixes = new Set(Object.values(UPLOAD_KINDS).map((s) => s.prefix));

  /** Bytes this user already holds across confirmed uploads. */
  async usedBytes(userId: string): Promise<number> {
    const agg = await this.prisma.fileObject.aggregate({
      where: { userId },
      _sum: { sizeBytes: true },
    });
    return agg._sum.sizeBytes ?? 0;
  }

  async quota(userId: string) {
    const used = await this.usedBytes(userId);
    return { usedBytes: used, quotaBytes: USER_STORAGE_QUOTA_BYTES, remainingBytes: Math.max(0, USER_STORAGE_QUOTA_BYTES - used) };
  }

  /**
   * Issues a presigned upload for the given owner + kind. Rejects a disallowed
   * content-type, a declared size over the per-file cap, and — critically — a file
   * that would push the user past their 1 GB quota (checked against `declaredBytes`;
   * the real size is re-checked at confirm).
   */
  async presignUpload(ownerId: string, kind: string, contentType: string, declaredBytes: number) {
    const spec = UPLOAD_KINDS[kind];
    if (!spec) throw new BadRequestException('Unknown upload kind.');
    await this.assertMayUpload(ownerId, kind, spec);
    const ct = contentType?.toLowerCase().trim();
    if (!spec.contentTypes.includes(ct)) {
      throw new BadRequestException(`Unsupported file type. Allowed: ${spec.contentTypes.join(', ')}.`);
    }
    if (!Number.isFinite(declaredBytes) || declaredBytes <= 0) {
      throw new BadRequestException('A positive file size is required.');
    }
    if (declaredBytes > spec.maxBytes) {
      throw new BadRequestException(`That file is too large. Max ${(spec.maxBytes / 1024 / 1024).toFixed(0)} MB.`);
    }

    const { remainingBytes } = await this.quota(ownerId);
    if (declaredBytes > remainingBytes) {
      throw new BadRequestException(
        'This upload would exceed your 1 GB storage. Delete a file, or email us for a secure upload link.',
      );
    }

    const key = `${spec.prefix}/${ownerId}/${randomUUID()}.${EXT[ct] ?? 'bin'}`;
    const presigned = await this.storage.presignUpload({
      key,
      contentType: ct,
      // The exact size the client just declared — signed into the URL, so this
      // presign can only be spent on a body of precisely that length.
      contentLength: declaredBytes,
      maxBytes: spec.maxBytes,
    });
    return { ...presigned, maxBytes: spec.maxBytes, kind };
  }

  /**
   * Records an uploaded object after the client's PUT succeeds. Re-checks the quota
   * against the ACTUAL size (the presign estimate can be gamed), so the 1 GB ceiling
   * holds even if a client lied about `declaredBytes`.
   */
  async confirmUpload(ownerId: string, kind: string, key: string, contentType: string, sizeBytes: number) {
    if (!(kind in UPLOAD_KINDS)) throw new BadRequestException('Unknown upload kind.');
    // Re-checked here, not only at presign, for the same reason the quota is: a client
    // holding an unexpired presigned URL (or one issued while they were still Premium)
    // must not be able to register the object after the entitlement is gone.
    await this.assertMayUpload(ownerId, kind, UPLOAD_KINDS[kind]);
    this.assertOwnedKey(ownerId, key);
    if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) throw new BadRequestException('Invalid file size.');

    // The quota check must be ATOMIC with the insert: two concurrent confirms both
    // reading the same used-total could each pass and both commit, exceeding 1 GB.
    // Serializable makes them conflict — the loser retries/aborts instead. (Same
    // read-sum-write race we closed on the bequest cap.)
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const agg = await tx.fileObject.aggregate({ where: { userId: ownerId }, _sum: { sizeBytes: true } });
          const used = agg._sum.sizeBytes ?? 0;
          if (used + sizeBytes > USER_STORAGE_QUOTA_BYTES) {
            throw new BadRequestException('This upload exceeds your 1 GB storage.');
          }
          return tx.fileObject.create({
            data: {
              userId: ownerId,
              kind,
              key,
              contentType,
              sizeBytes,
              // Quarantine the object until a scanner clears it, when scanning is on.
              scanStatus: this.malwareScanEnabled ? 'PENDING' : 'CLEAN',
            },
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (e: any) {
      if (e instanceof BadRequestException) throw e;
      // Duplicate key (the same object confirmed twice) is idempotent-ish: surface
      // it as a clean 400 rather than a 500.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw new BadRequestException('This file was already confirmed.');
      }
      throw e;
    }
  }

  /** Lists a user's files of a given kind (e.g. their legacy videos). */
  listForUser(ownerId: string, kind?: string) {
    return this.prisma.fileObject.findMany({
      where: { userId: ownerId, ...(kind ? { kind } : {}) },
      orderBy: { createdAt: 'desc' },
    });
  }

  /** Deletes a file the user owns, freeing quota. */
  async deleteOwned(ownerId: string, id: string) {
    const file = await this.prisma.fileObject.findUnique({ where: { id } });
    if (!file || file.userId !== ownerId) throw new BadRequestException('File not found.');
    await this.prisma.fileObject.delete({ where: { id } });
    return { deleted: true };
  }

  /**
   * Verifies a stored key was issued by us AND belongs to `ownerId`. Prevents a user
   * pinning another user's object key — the upload-side equivalent of IDOR.
   */
  assertOwnedKey(ownerId: string, key: string): void {
    const parts = key.split('/'); // <prefix>/<ownerId>/<uuid>.<ext>
    if (parts.length !== 3 || !FilesService.prefixes.has(parts[0]) || parts[1] !== ownerId) {
      throw new BadRequestException('That file does not belong to you.');
    }
  }

  /**
   * A short-lived download URL for one of OUR objects. The caller must already
   * have proven ownership (assertOwnsKey / a will-scoped read). We pin the served
   * Content-Type to the allow-listed type for the file's KIND — never the stored,
   * possibly-spoofed metadata — and force `attachment` for everything except a
   * legacy video, which plays inline. So a file whose bytes are HTML/JS can never
   * be served as text/html and executed in the app origin.
   *
   * TODO (AWS): refuse to serve unless scanStatus === CLEAN once GuardDuty
   * Malware Protection for S3 is wired — see docs/UPLOAD_SECURITY_AWS.md.
   */
  async presignDownload(key: string): Promise<string> {
    const file = await this.prisma.fileObject.findUnique({ where: { key } });
    // FAIL CLOSED on an unrecorded object. This gate previously read
    // `if (file && file.scanStatus !== 'CLEAN')`, which SKIPPED the malware check
    // entirely when no FileObject row existed for the key — the one case where we
    // know the LEAST about the bytes was the one case we served without question.
    // A missing row is not evidence of safety: with no row there is no scan verdict,
    // no recorded owner and no kind to pin the content-type from. Every legitimately
    // uploaded object has a row (confirmUpload creates it in the same transaction as
    // the quota check), so denying here only ever refuses objects we never recorded.
    if (!file) {
      throw new ForbiddenException('This file is not available for download.');
    }
    // Malware-scan gate: never hand out a URL to a file that hasn't been cleared.
    // PENDING → still being scanned; INFECTED → blocked permanently.
    if (file.scanStatus !== 'CLEAN') {
      throw new ForbiddenException(
        file.scanStatus === 'INFECTED'
          ? 'This file failed a security scan and cannot be downloaded.'
          : 'This file is still being scanned. Try again shortly.',
      );
    }
    const isVideo = file.kind === 'video_legacy';
    const contentType =
      isVideo && file.contentType?.startsWith('video/') ? file.contentType : 'application/octet-stream';
    return this.storage.presignDownload(key, {
      contentType,
      disposition: isVideo ? 'inline' : 'attachment',
      filename: key.split('/').pop(),
    });
  }

  /**
   * A download URL for a file the CALLER OWNS, addressed by row id.
   *
   * Ownership is established server-side by exactly the mechanism deleteOwned uses:
   * load the row, require `file.userId === ownerId`. The id is never trusted on its
   * own, so guessing another user's id gets the same 'File not found.' as a
   * nonexistent one — no existence oracle. The key is then taken from the ROW, never
   * from the client, so the scan gate and content-type pinning in presignDownload
   * apply to the object we actually recorded.
   *
   * Owner-facing only. Heir/trustee access to a deceased owner's files is NOT reachable
   * from here — it has its own named door, presignDownloadForRelease, below. (This comment
   * used to say that access was "a separate, undecided design"; it is decided and built,
   * and leaving that sentence would have made a reader trust a boundary that had moved.)
   */
  async presignDownloadOwned(ownerId: string, id: string): Promise<{ url: string }> {
    return this.presignDownloadByRowId(ownerId, id);
  }

  /**
   * A download URL for a file belonging to a DECEASED owner whose will has been RELEASED,
   * for an heir or trustee holding a portal session.
   *
   * A SECOND, EXPLICITLY NAMED ENTRY POINT — same body as presignDownloadOwned, and that is
   * the point. The alternative was to relax presignDownloadOwned so a caller could pass
   * someone else's id, which would have put "the caller owns this" and "the caller has been
   * released this" behind one function and one name. Two doors mean `grep
   * presignDownloadForRelease` answers "who can read a dead person's files" exactly, and a
   * future change to the owner path cannot silently widen the estate path or vice versa.
   *
   * THE RELEASE CHECK IS NOT HERE. `ownerId` is proven by the caller (PortalService reads
   * it off the will the token names, after assertReleased). This function's only job is the
   * ownership match and the scan gate — the same contract presignDownloadOwned has.
   */
  async presignDownloadForRelease(ownerId: string, fileId: string): Promise<{ url: string }> {
    return this.presignDownloadByRowId(ownerId, fileId);
  }

  /**
   * A download URL for the death certificate an ADMIN is reviewing a claim against.
   *
   * A THIRD named door, for the same reason there is a second. Until it existed there was
   * no request any admin could make that returned these bytes: the claim stores a
   * /files/:id/download URL, that route is owner-scoped, and claim uploads are attributed
   * to the DECEASED owner. So the human review standing between a forged certificate and
   * a released estate was carried out without sight of the certificate.
   *
   * THE ADMIN CHECK IS NOT HERE — the route carries @Roles('ADMIN'), and
   * DeathClaimsService.certificateForReview proves the file is that claim's certificate
   * and passes the estate's ownerId. This function's only job is the ownership match and
   * the scan gate, exactly like the two doors above.
   */
  async presignDownloadForClaimReview(ownerId: string, fileId: string): Promise<{ url: string }> {
    return this.presignDownloadByRowId(ownerId, fileId);
  }

  /**
   * Shared body of the three named doors above: load the row, require it to belong to
   * `ownerId`, and take the KEY off the row so presignDownload's scan gate and
   * content-type pinning apply to the object we actually recorded. Guessing an id gets the
   * same 'File not found.' as a nonexistent one — no existence oracle.
   */
  private async presignDownloadByRowId(ownerId: string, id: string): Promise<{ url: string }> {
    const file = await this.prisma.fileObject.findUnique({ where: { id } });
    if (!file || file.userId !== ownerId) throw new BadRequestException('File not found.');
    return { url: await this.presignDownload(file.key) };
  }

  /**
   * Records an out-of-band malware-scan verdict for one object (called by the
   * signed /files/scan-callback that AWS GuardDuty → EventBridge invokes). A CLEAN
   * verdict makes the file downloadable; an INFECTED one blocks it forever and
   * deletes the bytes from storage so the object can never be fetched or spread.
   */
  async applyScanResult(key: string, clean: boolean): Promise<{ scanStatus: string }> {
    const file = await this.prisma.fileObject.findUnique({ where: { key } });
    if (!file) throw new NotFoundException('Unknown file.');
    const scanStatus = clean ? 'CLEAN' : 'INFECTED';
    await this.prisma.fileObject.update({ where: { key }, data: { scanStatus } });
    if (!clean) {
      // Purge the malicious bytes; the row stays as an INFECTED tombstone for audit.
      //
      // ALL versions, not just the current one: a delete marker would leave the malware
      // fetchable by version id, and a presigned PUT is reusable within its TTL so one
      // key can hold several infected versions. Recoverability is an anti-goal here.
      // The failure is logged rather than swallowed — it used to be `.catch(() => undefined)`,
      // which let infected bytes live on in storage silently and forever.
      try {
        const erased = await this.storage.deleteAllVersions(key);
        if (!erased.verifiedEmpty) {
          this.logger.error(`INFECTED object ${key} may still be present in storage after erase.`);
        }
      } catch (e) {
        this.logger.error(`Failed to erase INFECTED object ${key}: ${(e as Error).message}`);
      }
    }
    return { scanStatus };
  }
}
