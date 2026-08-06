import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
// TYPE-only (erased at compile time) + a lazy require inside getBrowser(): puppeteer
// is an ESM-only package that drags in the whole Chromium module graph, and a process
// that never prints a document should never load it. Importing it eagerly also pulled
// it into the module graph of every test that merely touches a service downstream of
// this one, which a CJS jest runtime cannot load at all.
import type { Browser } from 'puppeteer';

export interface PdfRenderOptions {
  /** Page margins. Defaults suit a formal A4 document. */
  margin?: { top: string; bottom: string; left: string; right: string };
}

const DEFAULT_MARGIN = { top: '20mm', bottom: '20mm', left: '18mm', right: '18mm' };

/**
 * Renders HTML to a print-ready A4 PDF via headless Chromium.
 *
 * Chromium rather than a low-level PDF library (pdfkit / pdf-lib) because these
 * documents contain Arabic: those libraries have no Arabic shaping or bidi
 * reordering, so they emit disconnected, reversed letters. Chromium's text engine
 * handles shaping, bidi and RTL correctly — non-negotiable for a Sharia will, and
 * equally required for an Arabic receipt.
 *
 * ONE browser for the whole process, launched at boot (see onModuleInit) and reused.
 * It lives here rather than inside each document service so that adding a second
 * kind of document (wills, invoices, …) does not add a second ~150MB Chromium.
 */
@Injectable()
export class PdfRendererService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PdfRendererService.name);
  private browser?: Browser;
  /** In-flight launch, so concurrent first renders share one browser. */
  private launching?: Promise<Browser>;

  private async getBrowser(): Promise<Browser> {
    if (this.browser?.connected) return this.browser;
    // Two requests arriving before the first launch resolves must not each launch
    // a browser (the second would leak — the field is overwritten).
    if (this.launching) return this.launching;

    // In the container we use the distro's Chromium (see Dockerfile) rather than
    // Puppeteer's bundled build, which is glibc-only and fails on Alpine/musl.
    const executablePath = process.env.PUPPETEER_EXECUTABLE_PATH || undefined;
    this.launching = import('puppeteer')
      .then(({ default: puppeteer }) =>
        puppeteer.launch({
          headless: true,
          executablePath,
          args: ['--no-sandbox', '--disable-setuid-sandbox'], // required in most containers
        }),
      )
      .then((b) => {
        this.browser = b;
        return b;
      })
      .finally(() => {
        this.launching = undefined;
      });
    return this.launching;
  }

  /**
   * Launch Chromium at boot rather than on the first document.
   *
   * Lazy-on-first-render was costing the first reader the entire browser launch —
   * seconds in the container, minutes on a cold Windows dev machine — while the
   * Flutter client gave up at its 20s receiveTimeout and drew "The preview could not
   * be rendered". The document viewer therefore looked broken after every restart,
   * and was fine on a retry, which is the most misleading failure shape there is.
   *
   * Deliberately NOT awaited: a missing or unlaunchable Chromium must degrade to
   * "documents fail" and not "the API refuses to boot", and nothing else in the app
   * depends on the browser being up. render() still awaits getBrowser(), so a request
   * arriving mid-launch simply joins the in-flight promise.
   */
  onModuleInit() {
    void this.getBrowser().then(
      () => this.logger.log('Chromium ready — document rendering warm.'),
      (e) =>
        this.logger.error(
          `Chromium failed to launch; document rendering will fail until this is fixed: ${e?.message ?? e}`,
        ),
    );
  }

  async onModuleDestroy() {
    await this.browser?.close().catch(() => undefined);
  }

  async render(html: string, opts: PdfRenderOptions = {}): Promise<Buffer> {
    const browser = await this.getBrowser();
    const page = await browser.newPage();
    try {
      await page.setContent(html, { waitUntil: 'load' });
      // Any embedded @font-face must finish loading, or Chromium prints with a
      // fallback font (or tofu) before the face is ready.
      await page.evaluate(() => (document as any).fonts.ready);
      const pdf = await page.pdf({
        format: 'A4',
        printBackground: true,
        margin: opts.margin ?? DEFAULT_MARGIN,
      });
      return Buffer.from(pdf);
    } finally {
      await page.close().catch(() => undefined);
    }
  }
}
