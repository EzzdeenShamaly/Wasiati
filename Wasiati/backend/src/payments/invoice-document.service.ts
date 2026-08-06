import { Injectable } from '@nestjs/common';
import { PdfRendererService } from '../common/pdf/pdf-renderer.service';

export interface InvoiceDocumentData {
  id: string;
  issuedAt: Date;
  description: string;
  /** Total value of the invoice in MINOR units, INCLUDING any part paid by credit. */
  amountMinor: number;
  currency: string;
  /** Part of the total settled from account credit rather than a card. */
  creditAppliedMinor: number;
  status: string;
  billedToEmail: string;
  tier?: string | null;
  interval?: string | null;
  refundedAt?: Date | null;
}

/** HTML-escape — an invoice interpolates a user's email and a plan description. */
function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Minor units -> a display string. The currency CODE is printed rather than a
 * symbol: '$' is ambiguous across the US and Canadian markets we bill in, and an
 * invoice is the one document where the reader must not have to guess which
 * dollar they were charged.
 *
 * The code is escaped like any other interpolated value: it originates from an
 * admin-editable plan field, so it is not ours to trust just because it is short.
 */
function money(minor: number, currency: string): string {
  const major = (minor / 100).toFixed(2);
  return `${esc(currency.toUpperCase())} ${major}`;
}

function day(d: Date): string {
  // Fixed ISO-ish date, locale-independent: an invoice is a record, not a UI.
  return d.toISOString().slice(0, 10);
}

/**
 * The invoice document. English-only and deliberately plain: this is a financial
 * record that has to read the same to the customer, to support and to an auditor.
 *
 * Exported separately from the service so it can be tested without launching a
 * browser (mirrors buildWillHtml).
 */
export function buildInvoiceHtml(inv: InvoiceDocumentData): string {
  const charged = Math.max(0, inv.amountMinor - inv.creditAppliedMinor);
  const refunded = inv.status === 'REFUNDED';

  const rows: string[] = [
    `<tr><td>${esc(inv.description)}</td><td class="num">${money(inv.amountMinor, inv.currency)}</td></tr>`,
  ];
  // Only show the credit line when credit was actually used — otherwise a normal
  // card invoice grows a confusing "0.00" row.
  if (inv.creditAppliedMinor > 0) {
    rows.push(
      `<tr><td>Account credit applied</td><td class="num">-${money(inv.creditAppliedMinor, inv.currency)}</td></tr>`,
    );
  }

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Wasiati invoice ${esc(inv.id)}</title>
<style>
  * { box-sizing: border-box; }
  body {
    font-family: Georgia, 'Times New Roman', serif;
    color: #1C1B19;
    font-size: 12px;
    line-height: 1.6;
    direction: ltr;
    margin: 0;
  }
  .head { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #14532D; padding-bottom: 14px; }
  .brand { font-size: 22px; font-weight: 700; color: #14532D; letter-spacing: .02em; }
  .brand small { display: block; font-size: 10px; font-weight: 400; color: #6B6862; letter-spacing: .08em; text-transform: uppercase; }
  .meta { text-align: right; font-size: 11px; color: #6B6862; }
  .meta b { color: #1C1B19; }
  h1 { font-size: 15px; margin: 22px 0 4px; }
  .status { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em; padding: 3px 8px; border-radius: 99px;
            color: ${refunded ? '#8A5A00' : '#14532D'}; background: ${refunded ? '#FDF2DC' : '#E8F0E9'}; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  th, td { text-align: left; padding: 9px 0; border-bottom: 1px solid #E5E1D8; }
  th { font-size: 10px; text-transform: uppercase; letter-spacing: .06em; color: #6B6862; font-weight: 700; }
  .num { text-align: right; white-space: nowrap; }
  .total td { border-bottom: none; border-top: 2px solid #14532D; font-weight: 700; font-size: 13px; padding-top: 11px; }
  .note { margin-top: 26px; font-size: 10px; color: #6B6862; line-height: 1.7; border-top: 1px solid #E5E1D8; padding-top: 12px; }
</style>
</head>
<body>
  <div class="head">
    <div class="brand">Wasiati<small>wasiati.com</small></div>
    <div class="meta">
      <div><b>Invoice</b> ${esc(inv.id)}</div>
      <div>Date ${day(inv.issuedAt)}</div>
      <div>Billed to <b>${esc(inv.billedToEmail)}</b></div>
    </div>
  </div>

  <h1>Receipt</h1>
  <span class="status">${refunded ? 'REFUNDED' : 'PAID'}</span>
  ${inv.refundedAt ? `<div style="font-size:11px;color:#6B6862;">Refunded ${day(inv.refundedAt)}</div>` : ''}

  <table>
    <thead><tr><th>Description</th><th class="num">Amount</th></tr></thead>
    <tbody>
      ${rows.join('\n      ')}
      <tr class="total"><td>${inv.creditAppliedMinor > 0 ? 'Charged to card' : 'Total'}</td><td class="num">${money(charged, inv.currency)}</td></tr>
    </tbody>
  </table>

  <div class="note">
    Card payments are processed by Stripe — Wasiati never stores your card details.
    ${inv.creditAppliedMinor > 0 ? 'Part of this invoice was settled from your Wasiati account credit.' : ''}
    This receipt is issued by Wasiati for the subscription named above. Keep it for your records.
  </div>
</body>
</html>`;
}

/** Prints an invoice receipt via the shared Chromium. */
@Injectable()
export class InvoiceDocumentService {
  constructor(private pdf: PdfRendererService) {}

  renderPdf(inv: InvoiceDocumentData): Promise<Buffer> {
    return this.pdf.render(buildInvoiceHtml(inv), {
      margin: { top: '18mm', bottom: '18mm', left: '16mm', right: '16mm' },
    });
  }
}
