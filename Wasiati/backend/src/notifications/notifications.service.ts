import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Twilio from 'twilio';
import * as nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';

/** Redacts a phone/email to the last 4 chars so a skipped-send warning identifies the
 *  channel without writing the full PII (or, for SMS bodies, the OTP) to the log store. */
function maskDestination(to: string): string {
  const tail = to.slice(-4);
  return to.length <= 4 ? '****' : `***${tail}`;
}

/** Phone numbers reach us formatted inconsistently; compare them digit-for-digit. */
const normalizePhone = (p: string) => p.replace(/[\s-]/g, '');

/** A message captured by the dev outbox. Never populated outside dev — see below. */
export interface DevOutboxMessage {
  channel: 'sms' | 'whatsapp';
  to: string;
  body: string;
  sentAt: string;
}

/** How many messages the dev outbox keeps before evicting the oldest. */
const DEV_OUTBOX_LIMIT = 50;

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private client: Twilio.Twilio;
  private fromSms: string;
  private fromWhatsapp: string;
  private mailer?: Transporter;
  private mailFrom: string;

  /**
   * DEV ONLY. OTP codes and claim links deliberately leave the building over SMS and
   * nowhere else — the public endpoints never echo them, precisely so an anonymous
   * caller can never obtain a consumable credential (see DeathClaimsService.lookup,
   * whose response is byte-identical whether or not a link was in fact sent).
   * That leaves a local e2e run with no phone and no Twilio account no way to read a
   * code at all, so when explicitly enabled we keep recent message bodies in memory
   * for DevSmsController to serve: the SMS counterpart of the Mailhog inbox dev
   * already uses for email. The test then reads the code out-of-band, the same way a
   * real witness reads it off their handset — the API response stays identical for
   * authorized and unauthorized contacts, so the anti-enumeration property is intact.
   *
   * Triple-gated against production: this stays empty unless NODE_ENV !== production
   * AND OTP_DEV_ECHO=true; env.validation refuses that flag in production outright;
   * and DevModule (the only reader) is not registered there, so no route exists.
   */
  private readonly devOutbox: DevOutboxMessage[] = [];
  private readonly devOutboxEnabled: boolean;

  constructor(private config: ConfigService) {
    this.devOutboxEnabled =
      process.env.NODE_ENV !== 'production' && this.config.get<string>('OTP_DEV_ECHO') === 'true';
    if (this.devOutboxEnabled) {
      this.logger.warn('DEV SMS outbox is ON — message bodies (incl. OTPs) are readable at GET /dev/sms.');
    }

    const sid = this.config.get<string>('TWILIO_ACCOUNT_SID');
    const token = this.config.get<string>('TWILIO_AUTH_TOKEN');
    this.fromSms = this.config.get<string>('TWILIO_SMS_FROM') ?? '';
    this.fromWhatsapp = this.config.get<string>('TWILIO_WHATSAPP_FROM') ?? '';
    if (sid && token) {
      this.client = Twilio(sid, token);
    }

    // SMTP transport — Mailhog in dev, AWS SES (SMTP interface) in prod.
    this.mailFrom = this.config.get<string>('MAIL_FROM') ?? 'Wasiati <no-reply@wasiati.com>';
    const host = this.config.get<string>('SMTP_HOST');
    if (host) {
      const user = this.config.get<string>('SMTP_USER');
      const pass = this.config.get<string>('SMTP_PASS');
      this.mailer = nodemailer.createTransport({
        host,
        port: Number(this.config.get<string>('SMTP_PORT') ?? 587),
        secure: this.config.get<string>('SMTP_SECURE') === 'true',
        auth: user ? { user, pass } : undefined,
      });
    }
  }

  /**
   * Records a message in the dev outbox. A no-op unless the dev gate passed at
   * construction, so on any production path this costs one boolean check and keeps
   * no plaintext anywhere.
   */
  private captureForDevOutbox(channel: 'sms' | 'whatsapp', to: string, body: string): void {
    if (!this.devOutboxEnabled) return;
    this.devOutbox.push({ channel, to, body, sentAt: new Date().toISOString() });
    if (this.devOutbox.length > DEV_OUTBOX_LIMIT) this.devOutbox.shift();
  }

  /**
   * DEV ONLY. Messages captured for [destination] (or all of them), newest first.
   * Returns nothing at all when the dev gate is off, so a stray call can never
   * surface a live code.
   */
  readDevOutbox(destination?: string): DevOutboxMessage[] {
    if (!this.devOutboxEnabled) return [];
    const wanted = destination ? normalizePhone(destination) : null;
    return this.devOutbox
      .filter((m) => !wanted || normalizePhone(m.to) === wanted)
      .reverse();
  }

  /**
   * Sends a one-time code by SMS. Used for login MFA, witness signing, trustee confirmation.
   *
   * Returns whether the message was actually DISPATCHED. It used to return void, so an
   * unconfigured Twilio was indistinguishable from a delivered message. That mattered:
   * `email` is optional on the witness and trustee rosters while phone is required, so a
   * phone-only witness could receive nothing at all while the owner saw a clean success
   * and waited for a confirmation that had never been sent — and the will could not seal.
   * A send that reached nobody must not look like one that did.
   */
  async sendSms(to: string, body: string): Promise<boolean> {
    // Captured before the Twilio check so the outbox behaves identically whether or
    // not a dev machine happens to have credentials configured.
    this.captureForDevOutbox('sms', to, body);
    if (!this.client) {
      // NEVER log `body` — it carries the plaintext OTP. Log only that delivery was
      // skipped (masked recipient), so a misconfigured prod can't leak live codes.
      this.logger.warn(`Twilio not configured — SMS to ${maskDestination(to)} not sent.`);
      return false;
    }
    await this.client.messages.create({ to, from: this.fromSms, body });
    return true;
  }

  /**
   * True when WhatsApp can actually be used: a Twilio client AND a sender.
   *
   * Checked by the caller BEFORE choosing the channel, because the alternative — pick
   * WhatsApp, fail, fall back — costs the user a delay on every login. Without a sender
   * the `from` would be the literal string `whatsapp:`, which Twilio rejects.
   */
  get whatsappAvailable(): boolean {
    return !!this.client && this.fromWhatsapp.length > 0;
  }

  /**
   * Sends a one-time code over WhatsApp, as a cheaper alternative to SMS.
   *
   * Returns whether it was DISPATCHED, matching sendSms — it used to return void, which
   * meant a caller could not tell a delivered code from one that reached nobody. That
   * mattered the moment this channel became reachable: OtpService now refuses to report a
   * code as sent when it was not, and a void return would have silently opted WhatsApp out
   * of that guarantee.
   *
   * OPERATIONAL NOTE, unverifiable from here: Twilio requires business-initiated WhatsApp
   * messages to use a pre-approved template. A plain-text body works only inside a 24-hour
   * customer-initiated window, so the production sender needs an approved authentication
   * template before this path carries real traffic. It will surface as a Twilio API error
   * (not a silent drop) because this method lets the client's exception propagate.
   */
  async sendWhatsapp(to: string, body: string): Promise<boolean> {
    this.captureForDevOutbox('whatsapp', to, body);
    if (!this.whatsappAvailable) {
      // NEVER log `body` — it carries the plaintext OTP.
      this.logger.warn(`WhatsApp not configured — message to ${maskDestination(to)} not sent.`);
      return false;
    }
    await this.client!.messages.create({
      to: `whatsapp:${to}`,
      from: `whatsapp:${this.fromWhatsapp}`,
      body,
    });
    return true;
  }

  /**
   * Transactional email (verification, password reset, receipts, heir notifications).
   * Dev uses Mailhog; prod uses AWS SES over SMTP. `html` is optional; falls back to text.
   */
  /** Returns whether the mail was actually DISPATCHED — see sendSms for why this matters. */
  async sendEmail(to: string, subject: string, text: string, html?: string): Promise<boolean> {
    if (!this.mailer) {
      // Log only the masked recipient + subject — never the body (reset links, codes).
      this.logger.warn(`SMTP not configured — email to ${maskDestination(to)} not sent [${subject}].`);
      return false;
    }
    await this.mailer.sendMail({ from: this.mailFrom, to, subject, text, html: html ?? undefined });
    return true;
  }
}
