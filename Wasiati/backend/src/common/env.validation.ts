/**
 * Boot-time environment validation. Passed to ConfigModule.forRoot({ validate }),
 * so the app REFUSES TO START on a dangerous configuration rather than failing later
 * in a subtle way. No new dependency — a plain function, not Joi.
 *
 * We validate only the things whose absence/weakness is a security problem; optional
 * integration keys stay optional (their modules degrade to a clean 503).
 */
export function validateEnv(config: Record<string, unknown>): Record<string, unknown> {
  const errors: string[] = [];

  // The JWT signing secret. A short secret is brute-forceable; an unset one would
  // otherwise only fail deep inside passport at first use.
  const secret = String(config.SESSION_SECRET ?? '');
  if (!secret) {
    errors.push('SESSION_SECRET is required.');
  } else if (secret.length < 32) {
    errors.push('SESSION_SECRET must be at least 32 characters.');
  } else if (/^(replace-with|changeme|secret|password)/i.test(secret)) {
    errors.push('SESSION_SECRET is still a placeholder — set a real random value.');
  }

  if (!config.DATABASE_URL) {
    errors.push('DATABASE_URL is required.');
  }

  // OTP codes must never be echoed in production responses.
  if (process.env.NODE_ENV === 'production' && String(config.OTP_DEV_ECHO) === 'true') {
    errors.push('OTP_DEV_ECHO must not be true in production.');
  }

  // The base URL every SMS/email link is built from (see common/app-url.ts). A wrong or
  // missing value is invisible at runtime — the message sends, the recipient taps, and the
  // link goes nowhere — so it has to fail at boot instead. This was previously unset
  // everywhere and six services silently defaulted to the production host, which made
  // trustee confirmation and death claims untestable outside production.
  // APP_WEB_URL is the deprecated alias, accepted so an existing deployment keeps working.
  if (process.env.NODE_ENV === 'production' && !config.APP_BASE_URL && !config.APP_WEB_URL) {
    errors.push('APP_BASE_URL is required in production — every link in SMS/email is built from it.');
  }

  // The markets this stack holds accounts for. Unset, servedRegions() collapses to just the
  // deployment REGION, so a prod stack meant to serve US+CA+KSA would silently refuse every
  // Canadian and Saudi signup with a 400. Which markets a stack serves is a residency
  // decision — make it explicit in production, never an implicit default.
  if (process.env.NODE_ENV === 'production' && !config.SERVED_REGIONS) {
    errors.push('SERVED_REGIONS is required in production (e.g. "US,CA,KSA") — otherwise the stack silently refuses every market except REGION.');
  }

  // The allow-list of hosts a post-payment success/cancel URL may point at. Unset,
  // assertReturnUrl() validates NOTHING and accepts any client-supplied URL, so an
  // authenticated caller can hand a victim a genuine Stripe checkout that lands on
  // their own site afterwards (OWASP: unvalidated redirect). The guard exists in code;
  // this makes it impossible to ship with it silently switched off.
  if (process.env.NODE_ENV === 'production' && !config.PAYMENT_RETURN_HOSTS) {
    errors.push('PAYMENT_RETURN_HOSTS is required in production — unset, checkout return URLs are unvalidated.');
  }

  // TOTP secrets are sealed with a key derived from MFA_SECRET_KEY, falling back to
  // SESSION_SECRET (totp.service.ts). The fallback is convenient and quietly dangerous:
  // it welds two unrelated rotation schedules together. Rotate SESSION_SECRET — an
  // ordinary, encouraged thing to do after any suspected leak — and every enrolled
  // authenticator app stops verifying AT ONCE, for every user, with no error to explain
  // it. The whole MFA ladder pushes people onto TOTP precisely because it costs nothing
  // per login, so the blast radius grows with its success, and recovery means each of
  // them burning a backup code to re-enrol.
  //
  // Required in production BEFORE anyone enrols, because it cannot be introduced
  // afterwards: adding the key later changes the derived key and breaks exactly the
  // secrets it was meant to protect.
  if (process.env.NODE_ENV === 'production' && !config.MFA_SECRET_KEY) {
    errors.push(
      'MFA_SECRET_KEY is required in production — without it TOTP secrets are sealed with SESSION_SECRET, so rotating the session secret silently breaks every enrolled authenticator app.',
    );
  }

  // The refresh cookie is a 30-day bearer credential. Without Secure it may be sent over
  // cleartext http, and the flag defaults to FALSE, so forgetting it silently downgrades
  // session security rather than failing.
  if (process.env.NODE_ENV === 'production' && String(config.COOKIE_SECURE) !== 'true') {
    errors.push('COOKIE_SECURE must be "true" in production — the refresh cookie is a bearer credential.');
  }

  if (errors.length) {
    throw new Error(`Invalid environment configuration:\n  - ${errors.join('\n  - ')}`);
  }
  return config;
}
