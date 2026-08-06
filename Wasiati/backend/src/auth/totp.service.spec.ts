import { ConfigService } from '@nestjs/config';
import { authenticator } from 'otplib';
import { TotpService } from './totp.service';

/**
 * A TOTP secret is a bearer credential: whoever holds it can mint that user's second
 * factor forever. So the two things worth pinning are that a code actually validates
 * against a real authenticator's arithmetic, and that the stored form is useless to
 * anyone who walks off with the database.
 */
const svc = (over: Record<string, string> = {}) =>
  new TotpService({
    get: (k: string) => ({ SESSION_SECRET: 'a'.repeat(48), ...over })[k],
  } as unknown as ConfigService);

describe('TotpService', () => {
  it('accepts the code a real authenticator would show right now', () => {
    const s = svc();
    const secret = s.generateSecret();
    expect(s.verify(secret, authenticator.generate(secret))).toBe(true);
  });

  it('rejects a wrong code, a malformed one, and the empty string', () => {
    const s = svc();
    const secret = s.generateSecret();
    expect(s.verify(secret, '000000')).toBe(false);
    expect(s.verify(secret, 'abcdef')).toBe(false);
    expect(s.verify(secret, '12345')).toBe(false);
    expect(s.verify(secret, '')).toBe(false);
  });

  it('rejects another account\'s code', () => {
    const s = svc();
    const mine = s.generateSecret();
    const theirs = s.generateSecret();
    expect(s.verify(mine, authenticator.generate(theirs))).toBe(false);
  });

  it('tolerates whitespace, because authenticator apps display "123 456"', () => {
    const s = svc();
    const secret = s.generateSecret();
    expect(s.verify(secret, ` ${authenticator.generate(secret)} `)).toBe(true);
  });

  it('never throws on a corrupt secret — a broken row must read as a wrong code', () => {
    expect(svc().verify('not-a-valid-base32-secret!!', '123456')).toBe(false);
  });

  describe('storage', () => {
    it('seals and opens a round trip', () => {
      const s = svc();
      const secret = s.generateSecret();
      expect(s.open(s.seal(secret))).toBe(secret);
    });

    it('never stores the secret in the clear, and never repeats a ciphertext', () => {
      const s = svc();
      const secret = s.generateSecret();
      const a = s.seal(secret);
      const b = s.seal(secret);
      // A database dump must not hand over anyone's second factor.
      expect(a).not.toContain(secret);
      // Random IV per seal: identical secrets must not produce identical rows, or the
      // dump leaks which accounts share a secret.
      expect(a).not.toBe(b);
      expect(s.open(b)).toBe(secret);
    });

    it('refuses a row sealed under a DIFFERENT key rather than returning garbage', () => {
      const sealed = svc().seal('JBSWY3DPEHPK3PXP');
      // Rotating the root invalidates every enrolled authenticator — by design, and the
      // failure must be a clean null, not a crash or a wrong secret.
      expect(svc({ SESSION_SECRET: 'b'.repeat(48) }).open(sealed)).toBeNull();
    });

    it('detects tampering — GCM authenticates, it does not merely decrypt', () => {
      const s = svc();
      const sealed = s.seal('JBSWY3DPEHPK3PXP');
      const [v, iv, tag, data] = sealed.split('.');
      const flipped = Buffer.from(data, 'base64url');
      flipped[0] ^= 0xff;
      expect(s.open(`${v}.${iv}.${tag}.${flipped.toString('base64url')}`)).toBeNull();
    });

    it('returns null for absent or malformed values instead of throwing', () => {
      const s = svc();
      expect(s.open(null)).toBeNull();
      expect(s.open('')).toBeNull();
      expect(s.open('garbage')).toBeNull();
      expect(s.open('v9.a.b.c')).toBeNull();
    });

    it('uses a key DERIVED from the session secret, not the secret itself', () => {
      const root = 'a'.repeat(48);
      const sealed = svc().seal('JBSWY3DPEHPK3PXP');
      expect(sealed).not.toContain(root);
    });

    it('lets MFA_SECRET_KEY override the root, so the session secret can rotate alone', () => {
      const withOwnKey = svc({ MFA_SECRET_KEY: 'c'.repeat(48) });
      const sealed = withOwnKey.seal('JBSWY3DPEHPK3PXP');
      // Same dedicated key, different session secret -> still opens.
      expect(svc({ MFA_SECRET_KEY: 'c'.repeat(48), SESSION_SECRET: 'z'.repeat(48) }).open(sealed)).toBe(
        'JBSWY3DPEHPK3PXP',
      );
    });
  });

  it('builds a provisioning URI an authenticator app can scan', () => {
    const s = svc();
    const secret = s.generateSecret();
    const uri = s.provisioningUri('owner@example.com', secret);
    expect(uri).toContain('otpauth://totp/');
    expect(uri).toContain('Wasiati');
    expect(uri).toContain(`secret=${secret}`);
  });
});
