import { validateEnv } from './env.validation';

const base = { SESSION_SECRET: 'a'.repeat(40), DATABASE_URL: 'postgresql://x' };

/** A configuration that satisfies every production guard; override one to test it. */
const prod = (over: Record<string, unknown> = {}) => ({
  ...base,
  APP_BASE_URL: 'https://app.example',
  SERVED_REGIONS: 'US,CA,KSA',
  PAYMENT_RETURN_HOSTS: 'app.wasiati.com',
  COOKIE_SECURE: 'true',
  MFA_SECRET_KEY: 'b'.repeat(40),
  ...over,
});

describe('validateEnv', () => {
  const ORIGINAL = process.env.NODE_ENV;
  afterEach(() => {
    process.env.NODE_ENV = ORIGINAL;
  });

  it('accepts a sound configuration', () => {
    expect(() => validateEnv(base)).not.toThrow();
  });

  it('REFUSES to boot without a session secret', () => {
    expect(() => validateEnv({ ...base, SESSION_SECRET: '' })).toThrow(/SESSION_SECRET is required/);
  });

  it('REFUSES a short session secret', () => {
    expect(() => validateEnv({ ...base, SESSION_SECRET: 'tooshort' })).toThrow(/at least 32/);
  });

  it('REFUSES a placeholder secret', () => {
    expect(() => validateEnv({ ...base, SESSION_SECRET: 'replace-with-a-long-random-string' })).toThrow(
      /placeholder/,
    );
  });

  it('requires DATABASE_URL', () => {
    expect(() => validateEnv({ ...base, DATABASE_URL: undefined })).toThrow(/DATABASE_URL is required/);
  });

  it('REFUSES OTP_DEV_ECHO=true in production', () => {
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv({ ...base, OTP_DEV_ECHO: 'true' })).toThrow(/OTP_DEV_ECHO must not be true/);
  });

  it('allows OTP_DEV_ECHO=true outside production', () => {
    process.env.NODE_ENV = 'development';
    expect(() => validateEnv({ ...base, OTP_DEV_ECHO: 'true' })).not.toThrow();
  });

  it('REFUSES a missing SERVED_REGIONS in production', () => {
    // Unset, servedRegions() collapses to just REGION and silently refuses every other
    // market's signups — so production must state the markets it serves explicitly.
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv({ ...base, APP_BASE_URL: 'https://app.example', SERVED_REGIONS: '' })).toThrow(
      /SERVED_REGIONS is required/,
    );
  });

  it('accepts a full production configuration', () => {
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv(prod())).not.toThrow();
  });

  // Each of these defaults to "off" rather than "on", so forgetting one silently
  // WEAKENS production instead of breaking it — exactly the failure a boot guard is for.
  it('REFUSES a missing PAYMENT_RETURN_HOSTS in production (unvalidated checkout redirect)', () => {
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv(prod({ PAYMENT_RETURN_HOSTS: '' }))).toThrow(/PAYMENT_RETURN_HOSTS is required/);
  });

  it('REFUSES a refresh cookie without Secure in production', () => {
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv(prod({ COOKIE_SECURE: 'false' }))).toThrow(/COOKIE_SECURE must be "true"/);
    expect(() => validateEnv(prod({ COOKIE_SECURE: undefined }))).toThrow(/COOKIE_SECURE must be "true"/);
  });

  it('REFUSES a missing MFA_SECRET_KEY in production, before anyone can enrol', () => {
    // Unset, TOTP secrets are sealed with SESSION_SECRET. Rotating the session secret —
    // the correct move after any suspected leak — then breaks every enrolled
    // authenticator app at once, silently, and each user must burn a backup code. It
    // also cannot be fixed later: introducing the key changes the derived key and
    // destroys exactly the secrets it protects. So the guard has to bite before launch.
    process.env.NODE_ENV = 'production';
    expect(() => validateEnv(prod({ MFA_SECRET_KEY: '' }))).toThrow(/MFA_SECRET_KEY is required/);
    expect(() => validateEnv(prod({ MFA_SECRET_KEY: undefined }))).toThrow(/MFA_SECRET_KEY is required/);
  });

  it('does NOT demand MFA_SECRET_KEY in development — the fallback is a local convenience', () => {
    process.env.NODE_ENV = 'development';
    expect(() => validateEnv(base)).not.toThrow();
  });

  it('leaves all of it alone outside production, so local dev needs no ceremony', () => {
    process.env.NODE_ENV = 'development';
    expect(() => validateEnv(base)).not.toThrow();
  });

  it('reports EVERY problem at once, not just the first', () => {
    // A deploy that fixes one variable, reboots, and hits the next error is a slow way
    // to learn what production needs.
    process.env.NODE_ENV = 'production';
    try {
      validateEnv({ ...base });
      throw new Error('expected validateEnv to throw');
    } catch (e) {
      const msg = (e as Error).message;
      for (const key of ['APP_BASE_URL', 'SERVED_REGIONS', 'PAYMENT_RETURN_HOSTS', 'COOKIE_SECURE', 'MFA_SECRET_KEY']) {
        expect(msg).toContain(key);
      }
    }
  });
});
