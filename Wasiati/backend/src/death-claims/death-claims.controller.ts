import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { ClaimTokenScope } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ClaimScopes, ClaimToken, ClaimTokenContext, ClaimTokenGuard } from './claim-token.guard';
import { DeathClaimsService } from './death-claims.service';
import { ClaimLookupDto, SubmitDeathClaimDto, RejectDeathClaimDto } from './dto/death-claim.dto';

@ApiTags('death-claims')
@Controller()
export class DeathClaimsController {
  constructor(private deathClaims: DeathClaimsService) {}

  /**
   * THE way in — public, unauthenticated, and the only entry point to the claim flow.
   *
   * Always 202 with `{ acknowledged: true }`, whatever happens. The status code is part
   * of the contract, not decoration: a 404 for an unknown person and a 202 for a known
   * one is exactly the enumeration oracle this endpoint exists to avoid.
   *
   * This @Throttle is the per-IP first line only. The limits that matter — per-will and
   * per-destination — are enforced inside the service, because an attacker with a proxy
   * pool rotates past anything keyed on the IP.
   */
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @HttpCode(HttpStatus.ACCEPTED)
  @Post('death-claims/lookup')
  lookup(@Body() body: ClaimLookupDto) {
    return this.deathClaims.lookup(body.deceasedContact, body.claimantContact);
  }

  /**
   * Files the claim, authenticated ONLY by the single-use token from the lookup link.
   * willId, phone and role are read off the token; the body cannot influence them.
   *
   * This replaces POST /wills/:willId/death-claims and its /request companion, which
   * are deleted. Those took a caller-supplied willId and phone and answered with three
   * distinguishable errors — unknown will, known will with an unauthorised phone, and
   * authorised-but-no-code — which let anyone holding a will id enumerate the people
   * attached to it. Removing the caller-supplied identifiers removes the oracle
   * structurally, rather than flattening the error messages and hoping.
   */
  /**
   * Is this link still good? Nothing else — no state, no side effect.
   *
   * The guard is the whole implementation: it checks the hash, the expiry, the consumed
   * flag and the scope, and a dead link comes back 401 before any work happens. Without
   * this the FIRST request carrying the token was the presign, so a witness opening an
   * eight-day-old SMS link got the full form, typed his legal name, waited while a 4 MB
   * photograph was read into memory, and only then learned the link was dead — as red body
   * copy under the certificate card, with the form still filled in and no way forward.
   *
   * pcLinkInvalidTitle, pcLinkInvalidSub and pcStartOver were written and translated into
   * both locales for exactly that moment and were referenced nowhere in the app. This is
   * the call that lets the screen render them.
   */
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @UseGuards(ClaimTokenGuard)
  @ClaimScopes(ClaimTokenScope.CLAIM_SUBMIT)
  @Get('claim/session')
  @ApiOperation({ summary: 'Validate a claim link before showing the form. 401 if expired or used.' })
  session(@ClaimToken() claim: ClaimTokenContext) {
    // Deliberately not the willId or anything about the estate: this answers "is the link
    // alive", and an unauthenticated holder learns nothing else from it.
    return { ok: true as const, role: claim.role };
  }

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @UseGuards(ClaimTokenGuard)
  // A CLAIM_SUBMIT token and nothing else. A PORTAL_READ token is minted after release
  // so heirs can READ; it must never be replayable into filing a new claim.
  @ClaimScopes(ClaimTokenScope.CLAIM_SUBMIT)
  @Post('claim/submit')
  submit(@ClaimToken() claim: ClaimTokenContext, @Body() body: SubmitDeathClaimDto) {
    return this.deathClaims.submitClaim(claim, body.submittedByName, body.certificateFileId);
  }

  // --- Admin-only endpoints below (Phase 1 manual review queue) ---

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Get('admin/death-claims/pending')
  listPending() {
    return this.deathClaims.listPendingReview();
  }

  /**
   * The document the reviewer is deciding on. Until this route existed there was NO
   * request an admin could make that returned it: the claim's stored URL points at
   * /files/:id/download, which is owner-scoped, and claim uploads belong to the deceased.
   * The whole anti-fraud review ran blind.
   */
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Get('admin/death-claims/:claimId/certificate')
  @ApiOperation({ summary: "A short-lived link to this claim's death certificate, for review." })
  certificate(@Param('claimId') claimId: string) {
    return this.deathClaims.certificateForReview(claimId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/death-claims/:claimId/under-review')
  markUnderReview(@Param('claimId') claimId: string, @CurrentUser() admin: { userId: string }) {
    return this.deathClaims.markUnderReview(claimId, admin.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/death-claims/:claimId/approve')
  approve(@Param('claimId') claimId: string, @CurrentUser() admin: { userId: string }) {
    return this.deathClaims.approveAndSendSafetyCheck(claimId, admin.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/death-claims/:claimId/reject')
  reject(
    @Param('claimId') claimId: string,
    @CurrentUser() admin: { userId: string },
    @Body() body: RejectDeathClaimDto,
  ) {
    return this.deathClaims.reject(claimId, body.reason, admin.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/death-claims/:claimId/release')
  release(@Param('claimId') claimId: string, @CurrentUser() admin: { userId: string }) {
    return this.deathClaims.release(claimId, admin.userId);
  }
}
