/**
 * Runs before every spec file.
 *
 * Strips the DEV-ONLY env overrides a developer sets in backend/.env to make manual testing
 * bearable, so the suite always exercises the SHIPPED defaults.
 *
 * This is not hygiene, it is a real defect being closed. Raising
 * LOGIN_MFA_MAX_PER_WINDOW locally — so repeated logins stop hitting the 5/hour cap —
 * silently turned five security tests green that were asserting the cap still bites. A
 * setting that makes the tests agree with a developer's convenience instead of with
 * production is worse than no test: the suite reports the limit is enforced while the
 * process it ran in had the limit switched off.
 *
 * A spec that WANTS a non-default limit should set process.env itself and restore it,
 * which is explicit and local. Nothing should inherit it from the machine.
 */
/**
 * SET to the shipped default, not deleted.
 *
 * Deleting loses a race: a spec that bootstraps Nest pulls in ConfigModule, which loads
 * .env and puts the developer's override straight back. dotenv does NOT overwrite a value
 * already present in process.env, so writing the default here wins that race for good.
 */
const SHIPPED_DEFAULTS: Record<string, string> = {
  // Login second factor: 30s between codes, 5 per destination per hour.
  LOGIN_MFA_COOLDOWN_MS: '30000',
  LOGIN_MFA_MAX_PER_WINDOW: '5',
  // Global rate limit: 100 requests per 60s.
  THROTTLE_LIMIT: '100',
  THROTTLE_TTL_MS: '60000',
};

for (const [key, value] of Object.entries(SHIPPED_DEFAULTS)) {
  process.env[key] = value;
}
