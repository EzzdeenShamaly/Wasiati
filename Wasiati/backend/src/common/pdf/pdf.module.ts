import { Module } from '@nestjs/common';
import { PdfRendererService } from './pdf-renderer.service';

/** Shares ONE headless Chromium across every kind of document we print. */
@Module({
  providers: [PdfRendererService],
  exports: [PdfRendererService],
})
export class PdfModule {}
