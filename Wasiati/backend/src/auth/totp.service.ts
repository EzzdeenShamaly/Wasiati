import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { authenticator } from 'otplib';
import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'crypto';

/**
 * Authenticator-app second factor (TOTP, RFC 6238).
 *
 * This is the cost lever as much as a security one. MFA is mandatory on every password
 * login and the default channel is SMS, which at Saudi rates ($0.1949/message, 15.6x a US
 * one) is the single largest third-party line at scale. A TOTP code costs NOTHING to
 * deliver, and NIST SP 800-63B treats an authenticator app as stronger than SMS, which it
 * lists as a RESTRICTED authenticator. So the free option is also the better one.
 *
 * `otplib` was already a dependency and had never been imported; `User.mfaSecret` was
 * already in the schema, commented "encrypted at rest", and was never written. This fills
 * in both — including the encryption, which did not exist anywhere in the codebase.
 */
@Injectable()
export class TotpService {
  constructor(private config: ConfigService) {}

  /**
   * The key the TOTP secrets are sealed with.
   *
   * Derived via HKDF from MFA_SECRET_KEY when set, else from SESSION_SECRET — which is
   * already required, already validated (>=32 chars, no placeholders) and already the
   * app's most sensitive value, so it is a defensible root. A distinct `info` label means
   * this key cannot be confused with, or substituted for, anything else derived from it.
   *
   * CONSEQUENCE, worth knowing before rotating anything: change the root and every stored
   * TOTP secret becomes undecryptable, so every enrolled user must re-enrol. Set
   * MFA_SECRET_KEY explicitly if you ever want to rotate the session secret independently.
   */
  private key(): Buffer {
    const root = this.config.get<string>('MFA_SECRET_KEY') || this.config.get<string>('SESSION_SECRET') || '';
    return Buffer.from(hkdfSync('sha256', Buffer.from(root, 'utf8'), Buffer.alloc(0), 'wasiati:mfa:totp:v1', 32));
  }

  /** A fresh base32 secret for one user. Not persisted until they prove they scanned it. */
  generateSecret(): string {
    return authenticator.generateSecret();
  }

  /**
   * The `otpauth://` URI the authenticator app scans. The label carries the account so a
   * user with several accounts can tell them apart in a list of six-digit codes.
   */
  provisioningUri(email: string, secret: string): string {
    return authenticator.keyuri(email, 'Wasiati', secret);
  }

  /**
   * Checks a code against the secret, tolerating one step either side of now.
   *
   * The window is deliberate: phone clocks drift, and a user typing a code in the last
   * second of its 30-second step would otherwise be rejected for being punctual. One step
   * is the usual compromise — it widens the guess space to ~3 codes in 10^6, which is
   * still negligible against the login throttle.
   */
  verify(secret: string, token: string): boolean {
    const clean = (token ?? '').replace(/\s+/g, '');
    if (!/^\d{6}$/.test(clean)) return false;
    // otplib's options are global, so set them at the call site rather than trusting
    // whatever another import may have left behind.
    authenticator.options = { window: 1 };
    try {
      return authenticator.verify({ token: clean, secret });
    } catch {
      // A malformed/corrupt secret must read as "wrong code", never as a 500 that tells an
      // attacker they found an account whose secret is broken.
      return false;
    }
  }

  /**
   * Seals a secret for storage: AES-256-GCM, random IV, authentication tag retained.
   *
   * A TOTP secret is a bearer credential — anyone holding it can mint that user's second
   * factor forever. Storing it in plaintext would mean a single database dump hands over
   * the second factor of every enrolled account, which defeats the point of having one.
   * Format is `v1.<iv>.<tag>.<ciphertext>`, all base64url, so the version is visible if
   * the scheme ever has to change.
   */
  seal(secret: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key(), iv);
    const enc = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
    const b64 = (b: Buffer) => b.toString('base64url');
    return `v1.${b64(iv)}.${b64(cipher.getAuthTag())}.${b64(enc)}`;
  }

  /** Opens a sealed secret. Returns null on anything unexpected — never throws at a caller. */
  open(sealed: string | null): string | null {
    if (!sealed) return null;
    const [version, iv, tag, data] = sealed.split('.');
    if (version !== 'v1' || !iv || !tag || !data) return null;
    try {
      const decipher = createDecipheriv('aes-256-gcm', this.key(), Buffer.from(iv, 'base64url'));
      decipher.setAuthTag(Buffer.from(tag, 'base64url'));
      return Buffer.concat([decipher.update(Buffer.from(data, 'base64url')), decipher.final()]).toString('utf8');
    } catch {
      // Wrong key (the root was rotated) or a tampered row. Either way this user has no
      // usable authenticator and must re-enrol; it is not an error the login path can fix.
      return null;
    }
  }
}
