import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IdVerificationProvider, Region, VerificationStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { createHash, timingSafeEqual } from 'crypto';

/**
 * Nafath is Saudi Arabia's national identity/authentication service (National
 * Information Center). It's the correct KYC rail for KSA users — a document vendor
 * covers US/CA. Nafath is NOT a self-serve API: credentials + the exact endpoint
 * contract are issued by NIC during government onboarding, so this service is
 * config-gated and degrades to a clean 503 until NAFATH_API_KEY / NAFATH_BASE_URL
 * are set.
 *
 * Flow (MFA pattern):
 *   1. initiate(nationalId) -> Nafath returns a transId + a `random` number (1..N)
 *   2. the user opens the Nafath app and taps the matching number
 *   3. we learn the result by polling checkStatus(transId) OR a Nafath callback
 *
 * The request/response field names below follow the common Nafath MFA shape but
 * MUST be reconciled against the official integration guide you receive at
 * onboarding — they are intentionally isolated here so that's a one-file change.
 */
@Injectable()
export class NafathService {
  private readonly logger = new Logger(NafathService.name);

  constructor(
    private config: ConfigService,
    private prisma: PrismaService,
  ) {}

  private get baseUrl(): string | undefined {
    return this.config.get<string>('NAFATH_BASE_URL');
  }
  private get apiKey(): string | undefined {
    return this.config.get<string>('NAFATH_API_KEY');
  }

  private assertConfigured() {
    if (!this.baseUrl || !this.apiKey) {
      throw new ServiceUnavailableException('Nafath verification is not configured on this server.');
    }
  }

  private headers() {
    return {
      'Content-Type': 'application/json',
      // NIC typically issues an API key / app-id + app-key; adjust to the exact
      // auth scheme in your onboarding pack.
      Authorization: `Bearer ${this.apiKey}`,
      'APP-ID': this.config.get<string>('NAFATH_APP_ID') ?? '',
      'APP-KEY': this.config.get<string>('NAFATH_APP_KEY') ?? '',
    };
  }

  private mapStatus(nafathStatus: string | undefined): VerificationStatus {
    switch ((nafathStatus ?? '').toUpperCase()) {
      case 'COMPLETED':
      case 'APPROVED':
      case 'ACCEPTED':
        return VerificationStatus.VERIFIED;
      case 'REJECTED':
      case 'EXPIRED':
        return VerificationStatus.REJECTED;
      case 'WAITING':
      case 'PENDING':
        return VerificationStatus.PENDING;
      default:
        return VerificationStatus.PENDING;
    }
  }

  /**
   * Nafath only identifies Saudi residents, so it is only a valid rail for KSA
   * users. The client hides the CTA elsewhere, but the check has to live here —
   * the endpoint is reachable by any authenticated user.
   */
  private async assertSaudiUser(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { region: true } });
    if (!user) throw new BadRequestException('User not found.');
    if (user.region !== Region.KSA) {
      throw new ForbiddenException('Nafath verification is only available to users in Saudi Arabia.');
    }
  }

  /** Start a Nafath MFA request for the user's national ID. */
  async initiate(userId: string, nationalId: string) {
    this.assertConfigured();
    await this.assertSaudiUser(userId);
    if (!/^\d{10}$/.test(nationalId)) {
      throw new BadRequestException('A valid 10-digit Saudi national ID / Iqama number is required.');
    }

    let body: any;
    try {
      const res = await fetch(`${this.baseUrl}/api/v1/mfa/request`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify({ nationalId, service: 'Wasiati-KYC' }),
      });
      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        throw new ServiceUnavailableException(`Nafath error (${res.status}). ${detail.slice(0, 200)}`);
      }
      body = await res.json();
    } catch (err) {
      if (err instanceof ServiceUnavailableException || err instanceof BadRequestException) throw err;
      throw new ServiceUnavailableException('Could not reach Nafath. Please try again.');
    }

    const transId: string = body.transId ?? body.transactionId ?? body.id;
    const random: string | undefined = body.random ?? body.randomNumber;
    if (!transId) throw new ServiceUnavailableException('Nafath did not return a transaction id.');

    await this.prisma.nafathVerification.create({
      data: { userId, nationalId, transId, random: random ?? null, status: VerificationStatus.PENDING },
    });
    await this.prisma.user.update({
      where: { id: userId },
      data: {
        idVerificationStatus: VerificationStatus.PENDING,
        idVerificationProvider: IdVerificationProvider.NAFATH,
      },
    });

    // `random` is shown to the user so they can pick the matching number in the app.
    return { transId, random, status: VerificationStatus.PENDING };
  }

  /** Poll Nafath for the outcome of a transaction the caller owns. */
  async checkStatus(userId: string, transId: string) {
    this.assertConfigured();
    const record = await this.prisma.nafathVerification.findUnique({ where: { transId } });
    if (!record || record.userId !== userId) throw new BadRequestException('Verification not found.');

    let body: any;
    try {
      const res = await fetch(`${this.baseUrl}/api/v1/mfa/request/status?transId=${encodeURIComponent(transId)}`, {
        headers: this.headers(),
      });
      if (!res.ok) throw new ServiceUnavailableException(`Nafath status error (${res.status}).`);
      body = await res.json();
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      throw new ServiceUnavailableException('Could not reach Nafath. Please try again.');
    }

    const status = this.mapStatus(body.status);
    await this.persist(transId, userId, status);
    return { transId, status };
  }

  /**
   * Nafath can also push the result to a callback URL we register at onboarding.
   * Public endpoint — validate the shared secret before trusting the payload.
   */
  async handleCallback(payload: { transId?: string; status?: string; secret?: string }) {
    const expected = this.config.get<string>('NAFATH_CALLBACK_SECRET');
    // Fail CLOSED. This endpoint is public and unauthenticated (NIC posts to it
    // server-to-server), so the shared secret is its ONLY protection. If the secret is
    // not configured we cannot trust anything here — reject, rather than skip the check
    // and accept an attacker-supplied status. (Previously an unset secret let any
    // authenticated Saudi user self-mark VERIFIED by POSTing their own transId here.)
    if (!expected) {
      throw new ServiceUnavailableException('Nafath callback secret is not configured on this server.');
    }
    if (!payload.secret || !this.secretsMatch(payload.secret, expected)) {
      throw new BadRequestException('Invalid callback signature.');
    }
    if (!payload.transId) throw new BadRequestException('Missing transId.');
    const record = await this.prisma.nafathVerification.findUnique({ where: { transId: payload.transId } });
    if (!record) return { ok: true }; // unknown transaction — ignore quietly

    await this.persist(payload.transId, record.userId, this.mapStatus(payload.status));
    return { ok: true };
  }

  /** Constant-time secret comparison over fixed-length SHA-256 digests (no length leak). */
  private secretsMatch(a: string, b: string): boolean {
    const ha = createHash('sha256').update(a).digest();
    const hb = createHash('sha256').update(b).digest();
    return timingSafeEqual(ha, hb);
  }

  private async persist(transId: string, userId: string, status: VerificationStatus) {
    await this.prisma.nafathVerification.update({ where: { transId }, data: { status } });
    await this.prisma.user.update({
      where: { id: userId },
      data: { idVerificationStatus: status, idVerificationProvider: IdVerificationProvider.NAFATH },
    });
    this.logger.log(`Nafath ${transId} for user ${userId} -> ${status}`);
  }
}
