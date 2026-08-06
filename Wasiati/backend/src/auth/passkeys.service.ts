import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} from '@simplewebauthn/server';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { SessionUser } from './token.service';

const CHALLENGE_TTL_SECONDS = 300; // 5 minutes to complete the ceremony
const REG_PREFIX = 'passkey:reg:';
const AUTH_PREFIX = 'passkey:auth:';

/**
 * Passkeys (Face ID / Touch ID / Windows Hello / Chrome's platform authenticator)
 * via the WebAuthn standard, using @simplewebauthn/server.
 *
 * SECURITY: the WebAuthn challenge is generated and stored SERVER-SIDE in Redis,
 * keyed by an opaque sessionId returned to the client. On verify we read the
 * challenge back from Redis (single-use — deleted on read) and never trust a
 * challenge supplied in the request body. This closes the earlier hole where the
 * client passed `expectedChallenge` back and could have supplied any value.
 */
@Injectable()
export class PasskeysService {
  constructor(
    private config: ConfigService,
    private prisma: PrismaService,
    private redis: RedisService,
  ) {}

  private get rpName() {
    return 'Wasiati';
  }
  private get rpID() {
    return this.config.get<string>('PASSKEY_RP_ID') ?? 'wasiati.com';
  }
  private get origin() {
    return this.config.get<string>('PASSKEY_ORIGIN') ?? 'https://wasiati.com';
  }

  async generateRegistrationOptions(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found.');

    const options = await generateRegistrationOptions({
      rpName: this.rpName,
      rpID: this.rpID,
      userID: Buffer.from(user.id),
      userName: user.email,
      attestationType: 'none',
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
      },
    });

    const sessionId = randomUUID();
    await this.redis.setJson(
      `${REG_PREFIX}${sessionId}`,
      { challenge: options.challenge, userId },
      CHALLENGE_TTL_SECONDS,
    );
    return { options, sessionId };
  }

  async verifyRegistration(userId: string, sessionId: string, response: any) {
    const cached = await this.redis.takeJson<{ challenge: string; userId: string }>(`${REG_PREFIX}${sessionId}`);
    if (!cached || cached.userId !== userId) {
      throw new BadRequestException('Passkey challenge expired or invalid. Please try again.');
    }

    const verification = await verifyRegistrationResponse({
      response,
      expectedChallenge: cached.challenge,
      expectedOrigin: this.origin,
      expectedRPID: this.rpID,
    });

    if (!verification.verified || !verification.registrationInfo) {
      throw new BadRequestException('Passkey registration could not be verified.');
    }

    const { credential, credentialDeviceType } = verification.registrationInfo;
    await this.prisma.passkeyCredential.create({
      data: {
        userId,
        credentialId: credential.id,
        publicKey: Buffer.from(credential.publicKey).toString('base64'),
        counter: credential.counter,
        deviceType: credentialDeviceType,
        transports: credential.transports?.join(','),
      },
    });

    return { verified: true };
  }

  async generateAuthenticationOptions() {
    const options = await generateAuthenticationOptions({
      rpID: this.rpID,
      userVerification: 'preferred',
    });

    const sessionId = randomUUID();
    await this.redis.setJson(`${AUTH_PREFIX}${sessionId}`, { challenge: options.challenge }, CHALLENGE_TTL_SECONDS);
    return { options, sessionId };
  }

  /** Verifies the assertion and returns the authenticated user. Token issuance is the controller's job. */
  async verifyAuthentication(sessionId: string, response: any): Promise<{ user: SessionUser }> {
    const cached = await this.redis.takeJson<{ challenge: string }>(`${AUTH_PREFIX}${sessionId}`);
    if (!cached) throw new BadRequestException('Passkey challenge expired or invalid. Please try again.');

    const stored = await this.prisma.passkeyCredential.findUnique({
      where: { credentialId: response.id },
      include: { user: true },
    });
    if (!stored) throw new NotFoundException('Unrecognized passkey.');

    const verification = await verifyAuthenticationResponse({
      response,
      expectedChallenge: cached.challenge,
      expectedOrigin: this.origin,
      expectedRPID: this.rpID,
      credential: {
        id: stored.credentialId,
        publicKey: Buffer.from(stored.publicKey, 'base64'),
        counter: Number(stored.counter),
        transports: stored.transports?.split(',') as any,
      },
    });

    if (!verification.verified) throw new BadRequestException('Passkey authentication failed.');

    await this.prisma.passkeyCredential.update({
      where: { id: stored.id },
      data: { counter: verification.authenticationInfo.newCounter },
    });

    const u = stored.user;
    return { user: { id: u.id, email: u.email, region: u.region, role: u.role } };
  }
}
