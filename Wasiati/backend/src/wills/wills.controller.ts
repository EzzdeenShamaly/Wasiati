import { Body, Controller, Delete, Get, Header, Param, Patch, Post, Query, Req, Res, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { Request, Response } from 'express';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { WillsService } from './wills.service';
import { WillDocumentService, WillDocumentOptions } from './will-document.service';
import { CreateWillDto, AddBequestDto, SignWillDto, UpdateWillMessageDto, UpdateWillDraftDto, UpdateGuardianDto, WillStepUpDto } from './dto/will.dto';
import { CURRENT_DISCLAIMER_VERSION, DISCLAIMER_TEXT } from './disclaimer';

@ApiTags('wills')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('wills')
export class WillsController {
  constructor(
    private wills: WillsService,
    private documents: WillDocumentService,
    private prisma: PrismaService,
  ) {}

  // Declared before ':willId' so it isn't captured as a will id.
  @Get('disclaimer')
  disclaimer() {
    return { version: CURRENT_DISCLAIMER_VERSION, text: DISCLAIMER_TEXT };
  }

  @Post()
  create(@CurrentUser() user: { userId: string }, @Body() body: CreateWillDto) {
    return this.wills.create(user.userId, body.tier, body.heirs, body.madhhab);
  }

  @Get()
  list(@CurrentUser() user: { userId: string }) {
    return this.wills.listForOwner(user.userId);
  }

  @Get(':willId')
  findOne(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.wills.findOne(willId, user.userId);
  }

  /**
   * Print-ready PDF of the will. The user picks the shape and language:
   *   ?format=table|essay        (structured listing vs narrative prose)
   *   ?lang=en|ar                (Arabic is full RTL, shaped, Arabic-Indic numerals)
   *   ?display=percent|fraction  (fara'id shares as % — default — or canonical fractions)
   *
   * EXPORT GATE (spec §3): 403 until the required witnesses have signed AND the
   * trustee has confirmed; the error message spells out the progress.
   */
  @Get(':willId/pdf')
  @ApiOperation({
    summary:
      'Download this will as a PDF (format=table|essay, lang=en|ar, display=percent|fraction). Gated until witnesses + trustee confirm.',
  })
  @Header('Content-Type', 'application/pdf')
  async pdf(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Res() res: Response,
    @Query('format') format?: string,
    @Query('lang') lang?: string,
    @Query('display') display?: string,
  ): Promise<void> {
    // Ownership (404 for anyone else's will) + the witnesses-and-trustee export gate.
    await this.wills.assertExportable(willId, user.userId);
    const opts = this.docOptions(format, lang, display);
    const pdf = await this.renderWill(willId, user.userId, opts);
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="wasiati-will-${willId}-${opts.format}-${opts.lang}.pdf"`,
    );
    res.setHeader('Content-Length', pdf.length);
    res.end(pdf);
  }

  /**
   * The same document, rendered for READING rather than keeping.
   *
   * Deliberately NOT behind assertExportable. That gate exists so no executable copy of a
   * will can leave the system before the witnesses have signed and the trustee confirmed —
   * it is about the artifact, not about secrecy. The owner is looking at their own estate,
   * every figure of which the review screen already shows them, so refusing to render it
   * back protects nothing and leaves them signing a document they have never seen whole.
   *
   * The two differences from the download that matter:
   *   - inline, not attachment: this is for a viewer, and it never lands in Downloads;
   *   - the document marks its own state (buildHtml keys off status), so an unsealed will
   *     previews as an unsealed will rather than passing for an executed one.
   * Ownership is still enforced — findOne 404s on anyone else's will.
   */
  @Get(':willId/pdf/preview')
  @ApiOperation({
    summary:
      'Render this will for on-screen preview (format=table|essay, lang=en|ar, display=percent|fraction). Owner only; NOT export-gated.',
  })
  @Header('Content-Type', 'application/pdf')
  async pdfPreview(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Res() res: Response,
    @Query('format') format?: string,
    @Query('lang') lang?: string,
    @Query('display') display?: string,
  ): Promise<void> {
    const pdf = await this.renderWill(willId, user.userId, this.docOptions(format, lang, display));
    res.setHeader('Content-Disposition', 'inline');
    res.setHeader('Content-Length', pdf.length);
    res.end(pdf);
  }

  private docOptions(format?: string, lang?: string, display?: string): WillDocumentOptions {
    return {
      // Narrative unless 'table' is asked for by name (DECISIONS §29): the default
      // document reads as will language, matching what the app now shows first.
      format: format === 'table' ? 'table' : 'essay',
      lang: lang === 'ar' ? 'ar' : 'en',
      display: display === 'fraction' ? 'fraction' : 'percent',
    };
  }

  /**
   * Shared by the download and the preview so the two can never render different documents —
   * the whole point of previewing is that what you see is what you get. findOne enforces
   * ownership (404 otherwise), so the asset lookup below cannot leak another user's estate.
   */
  private async renderWill(willId: string, userId: string, opts: WillDocumentOptions): Promise<Buffer> {
    const will = await this.wills.findOne(willId, userId);
    const owner = await this.wills.ownerProfile(willId);
    const assets = await this.prisma.asset.findMany({ where: { willId } });
    return this.documents.renderPdf(
      {
        ...will,
        ownerEmail: owner.email,
        testatorCity: owner.addressCity,
        testatorCountry: owner.addressCountry,
        assets: assets.map((a) => ({
          type: a.type,
          label: a.label,
          institution: a.institution,
          estimatedValue: a.estimatedValue,
          currency: a.currency,
        })),
      },
      opts,
    );
  }

  @Post(':willId/bequests')
  addBequest(@CurrentUser() user: { userId: string }, @Param('willId') willId: string, @Body() body: AddBequestDto) {
    return this.wills.addBequest(willId, user.userId, body.beneficiaryName, body.sharePercent, body.notes);
  }

  /** Saves the owner's private "words for my family" letter (plain text, sanitised). */
  @Patch(':willId')
  updateMessage(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: UpdateWillMessageDto,
  ) {
    return this.wills.updateMessage(willId, user.userId, body.personalMessage);
  }

  /**
   * Autosave for the guided create flow (spec §3 autosave / acceptance #5).
   * Persists the client's form snapshot onto the DRAFT will ≤1s after a change;
   * the service also lifts heirs/wishes/words/bequest out of the snapshot so the
   * draft will row itself always mirrors what the user has entered.
   */
  @Patch(':willId/draft')
  @ApiOperation({ summary: 'Autosave the create-flow draft state onto a DRAFT will.' })
  updateDraft(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: UpdateWillDraftDto,
  ) {
    return this.wills.updateDraft(willId, user.userId, body.draftState);
  }

  /** Records guardianship of minor children (create-flow step 3). DRAFT-only. */
  @Patch(':willId/guardian')
  @ApiOperation({ summary: 'Set guardianship of minor children (mode: parent | islamic | named).' })
  updateGuardian(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: UpdateGuardianDto,
  ) {
    return this.wills.updateGuardian(willId, user.userId, body.mode, body.name, body.phone, body.email);
  }

  /** Owner digitally signs the will (DRAFT -> SIGNED); locks it from edits. */
  @Post(':willId/sign')
  sign(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: SignWillDto,
    @Req() req: Request,
  ) {
    return this.wills.signByOwner(willId, user.userId, body.signatureData, req.ip);
  }

  /** Owner seals the executed will (WITNESSED -> SEALED = published). */
  @Post(':willId/seal')
  seal(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.wills.seal(willId, user.userId);
  }

  /**
   * Issues the step-up code required by unpublish and delete (spec §3:
   * "Delete/unpublish require re-authentication: SMS OTP, or Face ID on mobile").
   * Sent by SMS when the owner has a phone, otherwise to their verified email; the
   * response's `via` field says which (DECISIONS §17).
   */
  @Post(':willId/step-up-otp')
  @ApiOperation({ summary: 'Send the re-authentication code (SMS, or email if no phone) for unpublish/delete.' })
  requestStepUpOtp(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.wills.requestStepUpOtp(willId, user.userId);
  }

  /** SEALED -> DRAFT. Step-up OTP required; signed witnesses are notified. */
  @Post(':willId/unpublish')
  @ApiOperation({ summary: 'Unpublish a sealed will back to draft (requires step-up OTP).' })
  unpublish(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: WillStepUpDto,
    @Req() req: Request,
  ) {
    return this.wills.unpublish(willId, user.userId, body.otp, req.ip);
  }

  /** Deletes a will permanently. Step-up OTP required; the action is audited. */
  @Delete(':willId')
  @ApiOperation({ summary: 'Delete a will (requires step-up OTP).' })
  remove(
    @CurrentUser() user: { userId: string },
    @Param('willId') willId: string,
    @Body() body: WillStepUpDto,
    @Req() req: Request,
  ) {
    return this.wills.remove(willId, user.userId, body.otp, req.ip);
  }

  /**
   * Opens the published will as a DRAFT revision that re-seals in its place
   * (spec §3) — no unpublish needed. The revision is the one allowed draft.
   */
  @Post(':willId/revise')
  @ApiOperation({ summary: 'Open the published will as a draft revision that replaces it when re-sealed.' })
  revise(@CurrentUser() user: { userId: string }, @Param('willId') willId: string) {
    return this.wills.revise(willId, user.userId);
  }
}
