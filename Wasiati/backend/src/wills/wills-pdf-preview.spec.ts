import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { WillsController } from './wills.controller';

/**
 * The will PREVIEW route.
 *
 * The owner could not read their own will before downloading it: the only PDF route was
 * behind assertExportable, so until two witnesses had signed and the trustee had confirmed
 * there was no way to see the document at all. The prototype shows the opposite — the will
 * rendered on the page with the Download button disabled above it — and signing a document
 * you have never seen whole is precisely the failure a will product cannot have.
 *
 * So the preview deliberately does NOT call assertExportable, and these tests pin why that
 * is safe rather than sloppy:
 *   - the gate protects the ARTIFACT, not the secrecy: it stops an executable copy leaving
 *     the system early. Reading is not keeping — the preview is served inline, never as an
 *     attachment.
 *   - ownership is still enforced, through findOne, which 404s on anyone else's will. That
 *     is the check that actually protects other people's estates, and it must not be
 *     relaxed with the gate.
 *   - an unsealed will still renders as "Draft — not yet sealed" (buildHtml keys off
 *     status), so a preview cannot be passed off as an executed will.
 *   - preview and download render through ONE code path, so what is read is what is kept.
 *     A preview that could disagree with the file is worse than no preview.
 */
describe('WillsController — PDF preview vs the export gate', () => {
  const USER = { userId: 'owner-1' };
  const WILL = 'will-1';

  const setup = (over: { exportable?: boolean } = {}) => {
    const rendered = Buffer.from('%PDF-1.7 rendered');
    const wills = {
      assertExportable: jest.fn().mockImplementation(async () => {
        if (over.exportable === false) throw new ForbiddenException('not yet');
      }),
      findOne: jest.fn().mockResolvedValue({ id: WILL, status: 'SIGNED', witnesses: [], trustees: [] }),
      ownerProfile: jest
        .fn()
        .mockResolvedValue({ email: 'owner@wasiati.test', addressCity: null, addressCountry: null }),
    } as any;
    const documents = { renderPdf: jest.fn().mockResolvedValue(rendered) } as any;
    const prisma = { asset: { findMany: jest.fn().mockResolvedValue([]) } } as any;
    const res: any = {
      headers: {} as Record<string, unknown>,
      setHeader(k: string, v: unknown) {
        this.headers[k] = v;
      },
      end: jest.fn(),
    };
    return { controller: new WillsController(wills, documents, prisma), wills, documents, res, rendered };
  };

  it('renders the preview even when the export gate is CLOSED', async () => {
    const { controller, res, rendered, wills } = setup({ exportable: false });
    await controller.pdfPreview(USER, WILL, res);
    expect(res.end).toHaveBeenCalledWith(rendered);
    expect(wills.assertExportable).not.toHaveBeenCalled();
  });

  it('still REFUSES the download while the gate is closed', async () => {
    const { controller, res } = setup({ exportable: false });
    await expect(controller.pdf(USER, WILL, res)).rejects.toBeInstanceOf(ForbiddenException);
    expect(res.end).not.toHaveBeenCalled();
  });

  it('serves the preview INLINE, never as an attachment', async () => {
    const { controller, res } = setup({ exportable: false });
    await controller.pdfPreview(USER, WILL, res);
    expect(res.headers['Content-Disposition']).toBe('inline');
  });

  it('the download is an attachment', async () => {
    const { controller, res } = setup();
    await controller.pdf(USER, WILL, res);
    expect(String(res.headers['Content-Disposition'])).toMatch(/^attachment;/);
  });

  it('enforces ownership on the preview — another user gets 404, gate or no gate', async () => {
    const { controller, res, wills } = setup({ exportable: false });
    wills.findOne.mockRejectedValue(new NotFoundException('Will not found.'));
    await expect(controller.pdfPreview(USER, WILL, res)).rejects.toBeInstanceOf(NotFoundException);
    expect(res.end).not.toHaveBeenCalled();
  });

  describe('the two toggles the app can now reach', () => {
    it('defaults to NARRATIVE + percent + en (DECISIONS §29)', async () => {
      // The default IS the decision: the document a caller gets without asking should
      // sound like a will, not an inventory printout. The table stays one param away.
      const { controller, res, documents } = setup();
      await controller.pdfPreview(USER, WILL, res);
      expect(documents.renderPdf).toHaveBeenCalledWith(
        expect.anything(),
        { format: 'essay', lang: 'en', display: 'percent' },
      );
    });

    it('honours format=essay and display=fraction', async () => {
      const { controller, res, documents } = setup();
      await controller.pdfPreview(USER, WILL, res, 'essay', 'ar', 'fraction');
      expect(documents.renderPdf).toHaveBeenCalledWith(
        expect.anything(),
        { format: 'essay', lang: 'ar', display: 'fraction' },
      );
    });

    it('still honours format=table by name — the rows are a choice, not gone', async () => {
      const { controller, res, documents } = setup();
      await controller.pdfPreview(USER, WILL, res, 'table', 'en', 'percent');
      expect(documents.renderPdf).toHaveBeenCalledWith(
        expect.anything(),
        { format: 'table', lang: 'en', display: 'percent' },
      );
    });

    it('falls back to the safe default on junk input rather than passing it through', async () => {
      const { controller, res, documents } = setup();
      await controller.pdfPreview(USER, WILL, res, 'nonsense', 'xx', 'nonsense');
      expect(documents.renderPdf).toHaveBeenCalledWith(
        expect.anything(),
        { format: 'essay', lang: 'en', display: 'percent' },
      );
    });

    it('preview and download render through the SAME options, so they cannot disagree', async () => {
      const a = setup();
      await a.controller.pdfPreview(USER, WILL, a.res, 'essay', 'ar', 'fraction');
      const b = setup();
      await b.controller.pdf(USER, WILL, b.res, 'essay', 'ar', 'fraction');
      expect(a.documents.renderPdf.mock.calls[0][1]).toEqual(b.documents.renderPdf.mock.calls[0][1]);
    });
  });
});
