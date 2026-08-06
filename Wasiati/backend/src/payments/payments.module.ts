import { Module } from '@nestjs/common';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { CatalogSyncService } from './catalog-sync.service';
import { CatalogSyncController } from './catalog-sync.controller';
import { SubscriptionsService } from './subscriptions.service';
import { InvoicesService } from './invoices.service';
import { InvoiceDocumentService } from './invoice-document.service';
import { StripeProvider } from './providers/stripe.provider';
import { PAYMENT_PROVIDER } from './payment-provider.interface';
import { ReferralsModule } from '../referrals/referrals.module';
import { CommerceModule } from '../commerce/commerce.module';
import { PdfModule } from '../common/pdf/pdf.module';

@Module({
  imports: [
    ReferralsModule, // referral rewards are granted from the payment webhook
    CommerceModule, // PromotionsService applies discounts to the charged amount
    PdfModule, // the shared Chromium that prints invoice receipts
  ],
  controllers: [PaymentsController, CatalogSyncController],
  providers: [
    PaymentsService,
    SubscriptionsService,
    // One-way mirror of our catalogue into the PSP, for its dashboard reporting.
    CatalogSyncService,
    // Receipts are OURS: we run our own billing cycle, so the PSP has no invoice
    // list to show the customer.
    InvoicesService,
    InvoiceDocumentService,
    // The PSP is behind a port so a second provider (or a Merchant of Record)
    // can be swapped in without touching PaymentsService.
    { provide: PAYMENT_PROVIDER, useClass: StripeProvider },
  ],
  exports: [PaymentsService],
})
export class PaymentsModule {}
