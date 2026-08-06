import { Body, Controller, Get, Header, Headers, Param, Post, Req, Res, UseGuards } from '@nestjs/common';
import { Response } from 'express';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { PaymentsService } from './payments.service';
import { InvoicesService } from './invoices.service';
import { ChangePaymentMethodDto, CreateCheckoutDto } from './dto/checkout.dto';

@ApiTags('payments')
@Controller('payments')
export class PaymentsController {
  constructor(
    private payments: PaymentsService,
    private invoices: InvoicesService,
  ) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('checkout')
  @ApiOperation({
    summary: 'Start a hosted checkout for a tier (live catalog + promo + account credit).',
    description:
      "Priced in the buyer's ACCOUNT region — there is deliberately no `region` field, so the currency " +
      'and price cannot be changed by the client. Rejects a one-time purchase of Ultimate.',
  })
  createCheckout(@CurrentUser() user: { userId: string }, @Body() dto: CreateCheckoutDto) {
    return this.payments.createCheckoutSession({
      userId: user.userId,
      tier: dto.tier,
      interval: dto.interval,
      promoCode: dto.promoCode,
      successUrl: dto.successUrl,
      cancelUrl: dto.cancelUrl,
    });
  }

  // --- "Manage billing" (spec §2) -------------------------------------------

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('billing')
  @ApiOperation({
    summary: 'Everything the Manage billing page shows: plan + renewal, card, invoices.',
    description:
      'Degrades honestly with no provider keys: `card` is null and `canChangeCard` false, while the plan, ' +
      'renewal date and invoices — all of which are ours — stay fully populated.',
  })
  billing(@CurrentUser() user: { userId: string }) {
    return this.payments.billingOverview(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('payment-method')
  @ApiOperation({
    summary: 'Start the hosted "change card" flow (a SetupIntent — no charge).',
    description:
      'Returns a redirect URL. The stored card is swapped only when the provider confirms the new one was ' +
      'tokenised, so abandoning the flow leaves the existing card untouched.',
  })
  changePaymentMethod(@CurrentUser() user: { userId: string }, @Body() dto: ChangePaymentMethodDto) {
    return this.payments.changePaymentMethod(user.userId, dto.successUrl, dto.cancelUrl);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('invoices')
  @ApiOperation({ summary: "The user's receipts, newest first." })
  invoiceList(@CurrentUser() user: { userId: string }) {
    return this.invoices.listForUser(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('invoices/:invoiceId/pdf')
  @ApiOperation({ summary: 'Download one of your own invoices as a PDF.' })
  @Header('Content-Type', 'application/pdf')
  async invoicePdf(
    @CurrentUser() user: { userId: string },
    @Param('invoiceId') invoiceId: string,
    @Res() res: Response,
  ): Promise<void> {
    // Owner-scoped inside the service: another customer's id 404s.
    const { pdf, filename } = await this.invoices.pdfForUser(user.userId, invoiceId);
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Length', pdf.length);
    res.end(pdf);
  }

  // NOTE: we deliberately use no hosted Billing Portal (that would be Stripe Billing,
  // which we avoid to keep the PSP swappable). WE are the billing portal: these
  // endpoints back it.

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('subscription')
  @ApiOperation({ summary: "The user's subscription: tier, status, renewal date, cancellation state." })
  subscription(@CurrentUser() user: { userId: string }) {
    return this.payments.mySubscription(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('subscription/resume')
  @ApiOperation({ summary: 'Undo a scheduled cancellation.' })
  resume(@CurrentUser() user: { userId: string }) {
    return this.payments.resume(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('subscription/cancel')
  @ApiOperation({ summary: 'Cancel at period end. Any burial plan is stopped and its contributions become refundable.' })
  cancel(@CurrentUser() user: { userId: string }) {
    return this.payments.cancelSubscription(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('burial-plan')
  @ApiOperation({ summary: "The user's prepaid burial plan(s) and the amount refundable on demand." })
  burialPlan(@CurrentUser() user: { userId: string }) {
    return this.payments.burialPlanStatus(user.userId);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('burial-plan/cancel')
  @ApiOperation({ summary: 'Stop contributing and get the contributions back. Never blocked.' })
  cancelBurialPlan(@CurrentUser() user: { userId: string }) {
    return this.payments.cancelBurialPlanForUser(user.userId, 'Cancelled by the user');
  }

  // --- admin: manage burial prepayment plans ---
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/burial-plans/:userId')
  @ApiOperation({ summary: 'Create a prepaid burial plan for a user.' })
  createBurialPlan(
    @Param('userId') userId: string,
    @Body() body: { currency: string; totalAmount: number; amountPaid?: number; maturesAt?: string },
  ) {
    return this.payments.createBurialPlan(userId, body);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/burial-plans/:planId/contribution')
  @ApiOperation({ summary: 'Record a contribution toward a grave (FULLY_FUNDED once covered).' })
  recordBurialContribution(@Param('planId') planId: string, @Body() body: { amount: number }) {
    return this.payments.recordBurialContribution(planId, body.amount);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Get('admin/burial-refunds')
  @ApiOperation({ summary: 'Cancelled burial plans whose contributions are still owed back.' })
  pendingBurialRefunds() {
    return this.payments.pendingBurialRefunds();
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('ADMIN')
  @Post('admin/burial-refunds/:planId/settle')
  @ApiOperation({ summary: 'Mark a burial refund as paid out (after moving the money).' })
  settleBurialRefund(@Param('planId') planId: string) {
    return this.payments.settleBurialRefund(planId);
  }

  // NOTE: raw body is required for webhook signature verification — registered in
  // main.ts (express.raw for this path) before the JSON body parser.
  @Post('webhook')
  webhook(@Req() req: any, @Headers('stripe-signature') signature: string) {
    return this.payments.handleWebhook(req.body, signature);
  }
}
