import { BadRequestException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac, timingSafeEqual } from 'crypto';
import {
  IdentityOutcome,
  IdentityProviderPort,
  IdentityRedaction,
  IdentityVerificationSession,
  IdentityWebhookEvent,
} from '../identity-provider.interface';

/**
 * Sumsub (sumsub.com) document + selfie KYC for the US/CA rail.
 *
 * Auth: every request is signed. `X-App-Access-Sig` is
 * HMAC-SHA256(secretKey, ts + METHOD + path + body) in hex, alongside `X-App-Token`
 * and `X-App-Access-Ts`. Our user id travels as Sumsub's `externalUserId`, so no
 * mapping table is needed.
 *
 * Webhooks are verified against `x-payload-digest`, whose algorithm Sumsub declares
 * in `x-payload-digest-alg` (HMAC_SHA1_HEX | HMAC_SHA256_HEX | HMAC_SHA512_HEX). The
 * digest is computed over the RAW body, so the route must not JSON-parse first.
 *
 * The exact endpoint paths follow Sumsub's published REST API, but MUST be
 * reconciled against the integration guide for your account's API version — they are
 * isolated here so that is a one-file change. This adapter has not yet been run
 * against the live API.
 */
@Injectable()
export class SumsubIdentityProvider implements IdentityProviderPort {
  readonly name = 'SUMSUB';
  private readonly logger = new Logger(SumsubIdentityProvider.name);

  constructor(private config: ConfigService) {}

  private get appToken(): string | undefined {
    return this.config.get<string>('SUMSUB_APP_TOKEN');
  }
  private get secretKey(): string | undefined {
    return this.config.get<string>('SUMSUB_SECRET_KEY');
  }
  private get webhookSecret(): string | undefined {
    return this.config.get<string>('SUMSUB_WEBHOOK_SECRET');
  }
  private get levelName(): string {
    return this.config.get<string>('SUMSUB_LEVEL_NAME') ?? 'basic-kyc-level';
  }
  private get baseUrl(): string {
    return this.config.get<string>('SUMSUB_BASE_URL') ?? 'https://api.sumsub.com';
  }

  /** True only when every credential needed to complete a verification is present. */
  get configured(): boolean {
    return !!(this.appToken && this.secretKey && this.webhookSecret);
  }

  /** Signs one request. `path` must include the query string exactly as sent. */
  private headersFor(method: string, path: string, body = ''): Record<string, string> {
    const ts = Math.floor(Date.now() / 1000).toString();
    const signature = createHmac('sha256', this.secretKey!)
      .update(ts + method.toUpperCase() + path + body)
      .digest('hex');
    return {
      'X-App-Token': this.appToken!,
      'X-App-Access-Sig': signature,
      'X-App-Access-Ts': ts,
      'Content-Type': 'application/json',
    };
  }

  /**
   * Returns a hosted WebSDK link the user is redirected to. Sumsub creates the
   * applicant on first use, keyed by our `externalUserId`, so this is idempotent
   * per user.
   */
  async createSession(params: { userId: string; email: string }): Promise<IdentityVerificationSession> {
    if (!this.configured) {
      throw new ServiceUnavailableException('Identity verification is not configured on this server.');
    }

    const query = new URLSearchParams({
      levelName: this.levelName,
      externalUserId: params.userId,
      ttlInSecs: '1800',
    });
    const path = `/resources/sdkIntegrations/levels/-/websdkLink?${query.toString()}`;

    let body: any;
    try {
      const res = await fetch(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers: this.headersFor('POST', path),
      });
      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        throw new ServiceUnavailableException(`Sumsub error (${res.status}). ${detail.slice(0, 200)}`);
      }
      body = await res.json();
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      throw new ServiceUnavailableException('Could not reach Sumsub. Please try again.');
    }

    const url: string | undefined = body?.url;
    if (!url) throw new ServiceUnavailableException('Sumsub did not return a verification link.');

    // The applicant id is not known until the user starts; the external id is ours.
    return { url, sessionId: params.userId };
  }

  /** Maps Sumsub's review answer onto our status. Anything unknown stays PENDING. */
  private static outcomeFrom(payload: any): IdentityOutcome {
    const answer: string | undefined = payload?.reviewResult?.reviewAnswer;
    if (answer === 'GREEN') return 'VERIFIED';
    if (answer === 'RED') return 'REJECTED';
    return 'PENDING';
  }

  private static digestAlgorithm(header?: string): string {
    switch ((header ?? 'HMAC_SHA1_HEX').toUpperCase()) {
      case 'HMAC_SHA512_HEX':
        return 'sha512';
      case 'HMAC_SHA256_HEX':
        return 'sha256';
      case 'HMAC_SHA1_HEX':
        return 'sha1';
      default:
        // Never guess at a digest we don't recognise: an unverifiable webhook must
        // be rejected, not waved through.
        throw new BadRequestException('Unsupported Sumsub webhook digest algorithm.');
    }
  }

  parseWebhook(rawBody: Buffer, signature: string, algorithm?: string): IdentityWebhookEvent {
    if (!this.webhookSecret) {
      throw new ServiceUnavailableException('Identity webhooks are not configured on this server.');
    }
    if (!signature) throw new BadRequestException('Missing Sumsub webhook signature.');

    const alg = SumsubIdentityProvider.digestAlgorithm(algorithm);
    const expected = createHmac(alg, this.webhookSecret).update(rawBody).digest('hex');

    // Constant-time compare; equal lengths first, since timingSafeEqual throws otherwise.
    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(signature, 'utf8');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new BadRequestException('Invalid Sumsub webhook signature.');
    }

    let payload: any;
    try {
      payload = JSON.parse(rawBody.toString('utf8'));
    } catch {
      throw new BadRequestException('Malformed Sumsub webhook body.');
    }

    const userId: string | undefined = payload?.externalUserId;
    if (!userId) throw new BadRequestException('Sumsub webhook carried no externalUserId.');

    const status = SumsubIdentityProvider.outcomeFrom(payload);
    this.logger.log(`Sumsub webhook: applicant ${payload?.applicantId ?? '?'} -> ${status}`);
    return { userId, status, providerRef: payload?.applicantId };
  }

  /**
   * NOT IMPLEMENTED for Sumsub, and reported as such rather than pretended.
   *
   * Sumsub is the fallback rail (Stripe Identity is the decided vendor, DECISIONS §13),
   * so this path only matters for a deployment still carrying Sumsub credentials. If one
   * ever goes live, this must call Sumsub's applicant-reset/deletion API — returning
   * `supported: false` makes the purge record honestly that the vendor still holds the
   * documents, instead of a tombstone quietly implying they were destroyed.
   */
  async redactPersonalData(): Promise<IdentityRedaction> {
    this.logger.warn(
      'Sumsub redaction is not implemented — verification documents remain at the vendor after a purge.',
    );
    return { provider: this.name, supported: false, sessionsFound: 0, redactionRequested: 0, alreadyRedacted: 0 };
  }
}
