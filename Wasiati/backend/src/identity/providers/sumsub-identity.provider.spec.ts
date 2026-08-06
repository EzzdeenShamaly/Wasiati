import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'crypto';
import { SumsubIdentityProvider } from './sumsub-identity.provider';

const SECRET = 'whsec_test';

const configWith = (over: Record<string, string | undefined> = {}) =>
  ({
    get: (k: string) =>
      ({
        SUMSUB_APP_TOKEN: 'app_tok',
        SUMSUB_SECRET_KEY: 'sk_test',
        SUMSUB_WEBHOOK_SECRET: SECRET,
        ...over,
      })[k],
  }) as unknown as ConfigService;

const sign = (body: Buffer, alg: 'sha1' | 'sha256' | 'sha512' = 'sha256') =>
  createHmac(alg, SECRET).update(body).digest('hex');

const payload = (over: Record<string, unknown> = {}) =>
  Buffer.from(
    JSON.stringify({
      applicantId: 'appl_1',
      externalUserId: 'user-1',
      type: 'applicantReviewed',
      reviewResult: { reviewAnswer: 'GREEN' },
      ...over,
    }),
  );

describe('SumsubIdentityProvider', () => {
  describe('configuration', () => {
    it('is configured only when every credential is present', () => {
      expect(new SumsubIdentityProvider(configWith()).configured).toBe(true);
      expect(new SumsubIdentityProvider(configWith({ SUMSUB_WEBHOOK_SECRET: undefined })).configured).toBe(false);
      expect(new SumsubIdentityProvider(configWith({ SUMSUB_APP_TOKEN: undefined })).configured).toBe(false);
    });

    it('refuses to start a session when unconfigured — never a silent pass', async () => {
      const svc = new SumsubIdentityProvider(configWith({ SUMSUB_SECRET_KEY: undefined }));
      await expect(svc.createSession({ userId: 'u1', email: 'a@b.com' })).rejects.toThrow(
        ServiceUnavailableException,
      );
    });
  });

  describe('parseWebhook', () => {
    const svc = () => new SumsubIdentityProvider(configWith());

    it('accepts a correctly signed GREEN review and maps it to VERIFIED', () => {
      const body = payload();
      expect(svc().parseWebhook(body, sign(body), 'HMAC_SHA256_HEX')).toEqual({
        userId: 'user-1',
        status: 'VERIFIED',
        providerRef: 'appl_1',
      });
    });

    it('maps RED to REJECTED, and an unknown answer to PENDING — never to VERIFIED', () => {
      const red = payload({ reviewResult: { reviewAnswer: 'RED' } });
      expect(svc().parseWebhook(red, sign(red), 'HMAC_SHA256_HEX').status).toBe('REJECTED');

      const unknown = payload({ reviewResult: {} });
      expect(svc().parseWebhook(unknown, sign(unknown), 'HMAC_SHA256_HEX').status).toBe('PENDING');

      const pending = payload({ type: 'applicantPending', reviewResult: undefined });
      expect(svc().parseWebhook(pending, sign(pending), 'HMAC_SHA256_HEX').status).toBe('PENDING');
    });

    it('REJECTS a forged signature — a wrong digest can never verify a user', () => {
      const body = payload();
      const forged = createHmac('sha256', 'not-the-secret').update(body).digest('hex');
      expect(() => svc().parseWebhook(body, forged, 'HMAC_SHA256_HEX')).toThrow(/Invalid Sumsub webhook signature/);
    });

    it('REJECTS a tampered body even with a signature valid for the original', () => {
      const original = payload({ reviewResult: { reviewAnswer: 'RED' } });
      const signature = sign(original);
      const tampered = payload({ reviewResult: { reviewAnswer: 'GREEN' } });
      expect(() => svc().parseWebhook(tampered, signature, 'HMAC_SHA256_HEX')).toThrow(/Invalid/);
    });

    it('rejects a missing signature rather than trusting the payload', () => {
      const body = payload();
      expect(() => svc().parseWebhook(body, '', 'HMAC_SHA256_HEX')).toThrow(/Missing/);
    });

    it('honours the algorithm Sumsub declares (sha1 and sha512)', () => {
      const body = payload();
      expect(svc().parseWebhook(body, sign(body, 'sha1'), 'HMAC_SHA1_HEX').status).toBe('VERIFIED');
      expect(svc().parseWebhook(body, sign(body, 'sha512'), 'HMAC_SHA512_HEX').status).toBe('VERIFIED');
    });

    it('defaults to sha1 when no algorithm header is sent (Sumsub’s default)', () => {
      const body = payload();
      expect(svc().parseWebhook(body, sign(body, 'sha1')).status).toBe('VERIFIED');
    });

    it('REFUSES an unrecognised digest algorithm rather than guessing', () => {
      const body = payload();
      expect(() => svc().parseWebhook(body, sign(body), 'HMAC_MD5_HEX')).toThrow(/Unsupported/);
    });

    it('rejects a signed payload that names no user', () => {
      const body = payload({ externalUserId: undefined });
      expect(() => svc().parseWebhook(body, sign(body), 'HMAC_SHA256_HEX')).toThrow(/no externalUserId/);
    });

    it('rejects a malformed body that is nonetheless correctly signed', () => {
      const body = Buffer.from('{not json');
      expect(() => svc().parseWebhook(body, sign(body), 'HMAC_SHA256_HEX')).toThrow(BadRequestException);
    });
  });
});
