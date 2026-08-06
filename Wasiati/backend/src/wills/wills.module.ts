import { Module } from '@nestjs/common';
import { WillsService } from './wills.service';
import { WillsController } from './wills.controller';
import { WillDocumentService } from './will-document.service';
import { AuthModule } from '../auth/auth.module';
import { PdfModule } from '../common/pdf/pdf.module';

// AuthModule provides OtpService for the delete/unpublish step-up re-authentication.
// PdfModule provides the shared headless Chromium the will PDF is printed with.
// NotificationsService and AuditService come from their @Global modules.
@Module({
  imports: [AuthModule, PdfModule],
  controllers: [WillsController],
  providers: [WillsService, WillDocumentService],
  // WillDocumentService is exported for the heir & trustee portal: the released estate
  // includes the will as a PDF, rendered by the SAME document service the owner's export
  // uses so the two can never drift apart.
  exports: [WillsService, WillDocumentService],
})
export class WillsModule {}
