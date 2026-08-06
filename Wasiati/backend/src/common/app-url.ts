import { ConfigService } from '@nestjs/config';

/**
 * The public base URL of the Flutter app, for links we put in SMS and email.
 *
 * WHY THIS EXISTS: six services each built this inline as
 *   `config.get('APP_BASE_URL') ?? 'https://app.wasiati.com'`
 * — trustee confirmation links, witness signing links, death-claim invites, the heir
 * portal link, retention notices and referral links. `APP_BASE_URL` was defined in NO
 * env file (grep: zero occurrences in `.env` and `.env.example`), so every one of those
 * links silently fell back to the production host. Locally that made the entire
 * confirmation and claim flow untestable — the link in the message pointed at a domain
 * the developer was not running — and on a deploy built from the documented variable
 * list it would inherit the same hardcoded default.
 *
 * It failed quietly in both directions, and four spec files INJECTED the variable, so the
 * suite was green over a setting that never existed at runtime.
 *
 * A second name made it worse: `APP_WEB_URL` was defined and read by exactly one file
 * (account-recovery). Two names for one concept, and the wrong one was wired. This module
 * is now the single accessor; `APP_WEB_URL` is accepted as a deprecated alias so an
 * existing deployment does not break on the rename.
 */

/** Trailing slashes stripped so callers can always append `/path`. */
function clean(url: string): string {
  return url.replace(/\/+$/, '');
}

/**
 * Resolves the app's base URL, or throws.
 *
 * Deliberately NO production fallback. A wrong link in a death-claim invite or a trustee
 * confirmation is invisible — the message sends, the recipient clicks, and nothing works —
 * so a misconfiguration must surface at boot (see validateEnv), not as a dead link in the
 * one message a grieving family receives. In development an unset value resolves to
 * localhost, because that is the only value that could be correct there.
 */
export function appBaseUrl(config: ConfigService): string {
  const configured = config.get<string>('APP_BASE_URL') ?? config.get<string>('APP_WEB_URL');
  if (configured) return clean(String(configured));

  if (process.env.NODE_ENV === 'production') {
    // Unreachable when validateEnv has run — kept so a direct call in a non-Nest context
    // (a script, a test harness) cannot silently mint production links either.
    throw new Error('APP_BASE_URL is required in production — links in SMS/email depend on it.');
  }
  return 'http://localhost:3000';
}
