import { Body, Controller, Get, Header, Post, Query, Req, Res, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ClaimTokenScope } from '@prisma/client';
import { Response } from 'express';
import { ClaimScopes, ClaimToken, ClaimTokenContext, ClaimTokenGuard } from '../death-claims/claim-token.guard';
import { WillDocumentOptions } from '../wills/will-document.service';
import { PortalService, PortalRequestMeta } from './portal.service';
import { PortalStartDto, PortalVerifyDto } from './portal.dto';

/** IP + user-agent for the audit trail and for an heir confirmation's evidentiary record. */
function metaOf(req: { ip?: string; headers?: Record<string, unknown> }): PortalRequestMeta {
  const ua = req.headers?.['user-agent'];
  return { ipAddress: req.ip, userAgent: typeof ua === 'string' ? ua : undefined };
}

/**
 * The heir & trustee portal.
 *
 * NOT ONE ROUTE HERE TAKES A WILL IDENTIFIER — no path parameter, no query, no body field.
 * Every read is scoped by the willId inside the token. That is deliberate and is the whole
 * of the scoping story: there is no per-route ownership check that a future endpoint could
 * forget to copy, because there is nothing for a caller to point at another estate.
 *
 * The scope declaration sits at CLASS level so a route added below cannot be admitted on a
 * CLAIM_SUBMIT token by omission, while ClaimTokenGuard is applied PER ROUTE because
 * `start` and `verify` are the public front door and must stay unauthenticated. (Metadata
 * with no guard is inert, so the class-level decorator costs those two nothing.)
 */
@ApiTags('portal')
@Controller('portal')
@ClaimScopes(ClaimTokenScope.PORTAL_READ)
export class PortalController {
  constructor(private portal: PortalService) {}

  // --- Public: sign-in --------------------------------------------------------

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('start')
  @ApiOperation({
    summary:
      'Send a portal sign-in code to the contact on file. Always { sent: true }, whether or not the address is on a will.',
  })
  start(@Body() body: PortalStartDto) {
    return this.portal.start(body.role, body.email);
  }

  @Throttle({ default: { limit: 6, ttl: 60000 } })
  @Post('verify')
  @ApiOperation({ summary: 'Exchange the code for an opaque, read-only portal session token.' })
  verify(@Body() body: PortalVerifyDto) {
    return this.portal.verify(body.role, body.email, body.code);
  }

  // --- Session: everything below reads willId out of the token ----------------

  @UseGuards(ClaimTokenGuard)
  @Get('me')
  @ApiOperation({ summary: 'Who this session is, and the claim status. Not gated on release.' })
  me(@ClaimToken() ctx: ClaimTokenContext) {
    return this.portal.me(ctx);
  }

  @UseGuards(ClaimTokenGuard)
  @Get('claim')
  @ApiOperation({ summary: 'Claim status, and once APPROVED the heir-confirmation roll-call.' })
  claim(@ClaimToken() ctx: ClaimTokenContext) {
    return this.portal.claim(ctx);
  }

  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseGuards(ClaimTokenGuard)
  @Post('claim/confirm')
  @ApiOperation({ summary: 'HEIR: record that you are ready for the will to be released.' })
  confirm(@ClaimToken() ctx: ClaimTokenContext, @Req() req: any) {
    return this.portal.confirm(ctx, metaOf(req));
  }

  /**
   * Accept the trusteeship without leaving the portal.
   *
   * Requiring CONFIRMED to read the estate would be a trap without this: the release notice
   * sends a trustee here, and the only other route to CONFIRMED is the /trustee/:id link
   * from the original invitation — mailed when the will was written, possibly years ago.
   */
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseGuards(ClaimTokenGuard)
  @Post('trustee/accept')
  @ApiOperation({ summary: 'TRUSTEE: accept the trusteeship, using this portal session as the proof.' })
  acceptTrusteeship(@ClaimToken() ctx: ClaimTokenContext, @Req() req: any) {
    return this.portal.confirmTrusteeship(ctx, metaOf(req));
  }

  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseGuards(ClaimTokenGuard)
  @Post('claim/override')
  @ApiOperation({ summary: 'TRUSTEE: release without the full heir roll-call. Recorded, never silent.' })
  override(@ClaimToken() ctx: ClaimTokenContext, @Req() req: any) {
    return this.portal.override(ctx, metaOf(req));
  }

  @UseGuards(ClaimTokenGuard)
  @Get('will')
  @ApiOperation({
    summary:
      'The released estate: personal message, fara’id shares, bequests, assets, funeral wishes, guardianship. Audited.',
  })
  will(@ClaimToken() ctx: ClaimTokenContext, @Req() req: any) {
    return this.portal.will(ctx, metaOf(req));
  }

  @UseGuards(ClaimTokenGuard)
  @Get('will/videos')
  @ApiOperation({ summary: 'Short-lived inline URLs for ALL legacy video messages, oldest first. Audited.' })
  videos(@ClaimToken() ctx: ClaimTokenContext, @Req() req: any) {
    return this.portal.videos(ctx, metaOf(req));
  }

  /**
   * The executed will as a PDF — same renderer and the same query switches as the owner's
   * export (`format=table|essay`, `lang=en|ar`, `display=percent|fraction`), so the heirs
   * receive exactly the document the testator proofread.
   */
  @UseGuards(ClaimTokenGuard)
  @Get('will/pdf')
  @ApiOperation({
    summary: 'The released will as a PDF (format=table|essay, lang=en|ar, display=percent|fraction). Audited.',
  })
  @Header('Content-Type', 'application/pdf')
  async pdf(
    @ClaimToken() ctx: ClaimTokenContext,
    @Req() req: any,
    @Res() res: Response,
    @Query('format') format?: string,
    @Query('lang') lang?: string,
    @Query('display') display?: string,
  ): Promise<void> {
    const opts: WillDocumentOptions = {
      // Narrative unless 'table' is asked for by name (DECISIONS §29) — this copy is
      // read by a bereaved family; it should sound like their person's will.
      format: format === 'table' ? 'table' : 'essay',
      lang: lang === 'ar' ? 'ar' : 'en',
      display: display === 'fraction' ? 'fraction' : 'percent',
    };
    const pdf = await this.portal.pdf(ctx, metaOf(req), opts);
    // The filename carries no will id — a portal holder has no use for the internal
    // identifier and it does not belong in their Downloads folder.
    res.setHeader('Content-Disposition', `attachment; filename="wasiati-will-${opts.format}-${opts.lang}.pdf"`);
    res.setHeader('Content-Length', pdf.length);
    res.end(pdf);
  }

  @UseGuards(ClaimTokenGuard)
  @Post('exit')
  @ApiOperation({ summary: 'End the session by burning the token server-side.' })
  exit(@ClaimToken() ctx: ClaimTokenContext) {
    return this.portal.exit(ctx);
  }
}
