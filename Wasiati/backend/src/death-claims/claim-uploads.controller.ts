import {
  BadRequestException,
  Body,
  Controller,
  Injectable,
  NotFoundException,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsInt, IsString, Min } from 'class-validator';
import { ClaimTokenScope } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { FilesService } from '../files/files.service';
// The one claim-credential seam, shared with the claim-submit route and the minting side:
// the hash and the scope-metadata key must be identical everywhere or a token silently
// stops verifying.
import { ClaimScopes, ClaimToken, ClaimTokenContext, ClaimTokenGuard } from './claim-token.guard';

/**
 * The ONLY kind a claim token may ever upload. Hardcoded here and never read from the body:
 * if `kind` were a request field this would be an unauthenticated write path into
 * video_legacy (500 MB a file) and id_document. Neither DTO below declares `kind`, and
 * whitelist:true strips it from the body, so there is no route by which a client value can
 * reach FilesService.
 */
const CLAIM_UPLOAD_KIND = 'death_certificate';

/** Key prefix FilesService issues for that kind. See UPLOAD_KINDS in files.service.ts. */
const CLAIM_UPLOAD_PREFIX = 'death-certificates/';

/**
 * Presigned write URLs one claim token may be issued.
 *
 * This used to be a single budget of two shared with confirm, which made the token buy
 * "one presign plus one confirm" — and made a dropped upload fatal. The client's PUT to
 * storage happens BETWEEN the two server calls; when it fails the server never hears about
 * it, so there is nothing to refund. The claimant retried, the second presign spent the
 * last slot, the PUT succeeded, and confirm was refused. No certificate stored, no way
 * forward, and the screen still offering the button that had just burned the link.
 *
 * A presign only hands out a write URL to a key under the estate's own prefix; nothing is
 * recorded until confirm. So retries are cheap and should be allowed — five covers a bad
 * connection and a wrong file type or two, and still bounds a leaked token.
 */
export const CLAIM_UPLOAD_OPERATION_CAP = 5;

/**
 * Death certificates one claim token may actually RECORD. This is the real invariant the
 * old shared budget was reaching for, and here it is exact rather than inferred from an
 * operation count.
 */
export const CLAIM_CONFIRM_CAP = 1;

export class ClaimPresignUploadDto {
  @IsString()
  contentType: string;

  @IsInt()
  @Min(1)
  sizeBytes: number;
}

export class ClaimConfirmUploadDto {
  @IsString()
  key: string;

  @IsString()
  contentType: string;

  @IsInt()
  @Min(1)
  sizeBytes: number;
}

/**
 * Death-certificate upload for someone with NO account.
 *
 * FilesController sits behind a class-level JwtAuthGuard and stays there — loosening it
 * would open every kind to every caller. This controller is a second, deliberately narrow
 * door onto the SAME FilesService: identical content-type allow-list, size cap, key
 * namespacing, quota transaction and assertOwnedKey, with the kind nailed shut and the
 * estate read out of the token.
 *
 * The object is attributed to the DECEASED OWNER (`will.ownerId`). FileObject.userId is a
 * required FK to User and a claimant has no User row, so the alternatives were a schema
 * change or a nullable owner; attributing it to the owner also makes the certificate purge
 * with the estate and count against the estate's quota, which is where it belongs.
 */
@Injectable()
@ApiTags('claim-uploads')
@Controller('claim/uploads')
@UseGuards(ClaimTokenGuard)
// A CLAIM_SUBMIT token, and only that. A PORTAL_READ token is minted after release to let
// heirs READ; it must never be replayable into a write. The guard fails closed if this
// decorator is ever dropped, so the two scopes cannot cross.
@ClaimScopes(ClaimTokenScope.CLAIM_SUBMIT)
export class ClaimUploadsController {
  constructor(
    private files: FilesService,
    private prisma: PrismaService,
  ) {}

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @Post('presign')
  @ApiOperation({
    summary:
      'Presign a death-certificate upload against a claim token. Kind is fixed server-side; the estate comes out of the token.',
  })
  async presign(@ClaimToken() claim: ClaimTokenContext, @Body() dto: ClaimPresignUploadDto) {
    const ownerId = await this.ownerIdOf(claim.willId);
    await this.consumeUploadSlot(claim.tokenId);
    try {
      return await this.files.presignUpload(ownerId, CLAIM_UPLOAD_KIND, dto.contentType, dto.sizeBytes);
    } catch (e) {
      // The slot is reserved BEFORE the presign so two concurrent calls cannot both pass the
      // cap; a presign that then fails validation granted no write capability, so give it
      // back. Otherwise a grieving claimant who picks the wrong file type twice is locked
      // out of filing at all, and a new token has to be sent by SMS.
      await this.refundUploadSlot(claim.tokenId);
      throw e;
    }
  }

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @Post('confirm')
  @ApiOperation({ summary: 'Record the uploaded death certificate against the estate, after the client PUT.' })
  async confirm(@ClaimToken() claim: ClaimTokenContext, @Body() dto: ClaimConfirmUploadDto) {
    const ownerId = await this.ownerIdOf(claim.willId);
    // assertOwnedKey (inside confirmUpload) proves the key is under THIS owner's prefix, but
    // it accepts any of the three upload prefixes. Pin ours as well: without this a claim
    // token could record a death_certificate row whose key points into the owner's
    // legacy-videos namespace. Guessing the UUID is infeasible, so this is depth, not the
    // only lock — but it costs two lines and closes the shape of the hole.
    if (!dto.key.startsWith(CLAIM_UPLOAD_PREFIX)) {
      throw new BadRequestException('That file does not belong to this claim.');
    }
    await this.consumeConfirmSlot(claim.tokenId);
    return this.files.confirmUpload(ownerId, CLAIM_UPLOAD_KIND, dto.key, dto.contentType, dto.sizeBytes);
  }

  /** The estate's owner — the id the object is attributed to. willId is never client-supplied. */
  private async ownerIdOf(willId: string): Promise<string> {
    const will = await this.prisma.will.findUnique({ where: { id: willId }, select: { ownerId: true } });
    if (!will) throw new NotFoundException('This link is no longer valid.');
    return will.ownerId;
  }

  /**
   * Claims one of the token's storage operations, atomically. The cap lives in the WHERE, so
   * the check and the increment are one statement and two concurrent requests cannot both
   * read `uploadCount = 1` and both proceed — the same updateMany-as-a-guard the OTP attempt
   * counter uses (otp.service.ts). `count === 0` means the cap was already reached.
   */
  private async consumeUploadSlot(tokenId: string): Promise<void> {
    const { count } = await this.prisma.claimAccessToken.updateMany({
      where: { id: tokenId, consumedAt: null, uploadCount: { lt: CLAIM_UPLOAD_OPERATION_CAP } },
      data: { uploadCount: { increment: 1 } },
    });
    if (count === 0) {
      // Distinct from the confirm message on purpose. Running out of ATTEMPTS is a
      // different situation from having already sent a document, and telling someone their
      // link is spent when they have not managed to send anything is both untrue and the
      // point at which they give up.
      throw new BadRequestException(
        'Too many upload attempts on this link. Request a new link and try again.',
      );
    }
  }

  /**
   * Claims the token's ONE recorded certificate, atomically and by the same
   * updateMany-as-a-guard. Separate from the presign budget so a failed upload costs an
   * attempt rather than the claimant's only route to filing.
   */
  private async consumeConfirmSlot(tokenId: string): Promise<void> {
    const { count } = await this.prisma.claimAccessToken.updateMany({
      where: { id: tokenId, consumedAt: null, confirmCount: { lt: CLAIM_CONFIRM_CAP } },
      data: { confirmCount: { increment: 1 } },
    });
    if (count === 0) {
      throw new BadRequestException('This link has already been used to send a document.');
    }
  }

  /** Gives back a slot reserved for an operation that then failed. Never goes below zero. */
  private async refundUploadSlot(tokenId: string): Promise<void> {
    await this.prisma.claimAccessToken
      .updateMany({ where: { id: tokenId, uploadCount: { gt: 0 } }, data: { uploadCount: { decrement: 1 } } })
      .catch(() => undefined);
  }
}
