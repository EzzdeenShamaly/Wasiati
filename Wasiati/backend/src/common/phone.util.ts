import { parsePhoneNumberFromString, type CountryCode } from 'libphonenumber-js';

/**
 * Phone normalisation for the death-claim path.
 *
 * WHY THIS EXISTS: the claim code used to compare phones with
 * `p.replace(/[\s-]/g, '')`, so a family member who typed `0555123456` could never
 * match the `+966555123456` the testator had recorded — the same line, rejected on the
 * one flow that has no second chance.
 *
 * WHY libphonenumber: the first fix compared a fixed-length tail of the digits, sized
 * to the shortest subscriber number among the four regions we deploy to. That cannot be
 * made correct for arbitrary countries, in EITHER direction:
 *   - too long, and it reaches into the country code — the Qatar bug (8-digit subscriber
 *     numbers) that a test caught only after the tail was set to 9;
 *   - too short, and unrelated numbers collide;
 *   - and any fixed minimum length silently REFUSES to match countries whose national
 *     numbers are shorter than it (Iceland 7, Solomon Islands 5), returning "not the same
 *     person" for a number that is plainly the same person.
 * There is no single tail length that is right everywhere, because there is no global
 * rule — only per-country numbering plans. Google's metadata is that data, so we use it
 * rather than approximate it. Contacts on a will are not restricted to our four
 * deployment regions: a testator in Riyadh may name a trustee in Cairo or Manchester.
 *
 * NOT a validator. It never rejects a number for being unusual; it canonicalises what it
 * is given so two spellings of one line land on one string. A number libphonenumber
 * cannot parse degrades to digit-normalisation rather than being thrown away.
 */

/**
 * Deployment region -> ISO-3166 country, used as the default parsing hint for a number
 * written in national form (a leading trunk `0`, or bare digits). `KSA` is the Prisma
 * Region member; `SA` is the ISO code for the same country, accepted so a caller can pass
 * either without a surprise.
 */
const REGION_TO_COUNTRY: Record<string, CountryCode> = {
  KSA: 'SA', // Prisma's Region member for Saudi Arabia; ISO-3166 calls it SA.
};

/**
 * Resolves a hint to an ISO-3166 country.
 *
 * Any two-letter code passes through unchanged — the map above exists ONLY to translate
 * our one non-ISO Region member. Restricting this to the deployment regions would have
 * reimposed the four-country assumption a level up: a will may name a trustee in Cairo,
 * and `phonesMatch(..., 'EG')` has to mean Egypt, not "no hint".
 */
function countryHint(regionHint?: string | null): CountryCode | undefined {
  const raw = (regionHint ?? process.env.REGION ?? '').trim().toUpperCase();
  if (!raw) return undefined;
  const mapped = REGION_TO_COUNTRY[raw];
  if (mapped) return mapped;
  return /^[A-Z]{2}$/.test(raw) ? (raw as CountryCode) : undefined;
}

/** Digits only, ignoring '+' and formatting. */
function digitsOf(raw: string): string {
  return raw.replace(/\D/g, '');
}

/**
 * Canonicalises a phone number to E.164 (`+<country><national>`).
 *
 *   '  +966 555-123-456 '        -> '+966555123456'
 *   '00966555123456'             -> '+966555123456'
 *   '0555123456' (REGION=KSA)    -> '+966555123456'
 *   '033123456'  (REGION=QA)     -> '+97433123456'
 *   '(415) 555-2671' (REGION=US) -> '+14155552671'
 *
 * A number that carries its own country code parses without any hint, so a trustee
 * abroad works regardless of which region the deployment serves.
 *
 * When the number cannot be parsed — a partial entry, a short code, a genuinely odd
 * string — it degrades to `+digits` (if it led with '+' or '00') or bare digits, so two
 * spellings still converge as far as they can. It is never discarded: refusing to
 * canonicalise is safe, inventing a country code is not.
 */
export function normalizePhone(raw: string | null | undefined, regionHint?: string | null): string {
  if (!raw) return '';
  const trimmed = String(raw).trim();
  if (!digitsOf(trimmed)) return '';

  // '00' is the international-access prefix in most of the world; libphonenumber reads
  // it correctly, but only when the string looks international. Normalising it to '+'
  // first makes the intent explicit and hint-independent.
  const candidate = /^00\d/.test(trimmed) ? `+${digitsOf(trimmed).slice(2)}` : trimmed;

  const hint = countryHint(regionHint);
  const parsed = parsePhoneNumberFromString(candidate, hint);
  if (parsed?.isValid()) return parsed.number;

  // Not a valid number as written. If it looks like national form with a trunk '0',
  // try again without it before giving up.
  //
  // Countries differ on whether that leading zero belongs: the UK's 07700 900123 needs
  // it, Qatar has no trunk prefix at all — yet people type one from habit. Parsing
  // '033123456' for QA yields +974033123456, a real-looking string for a line that does
  // not exist, which then compares unequal to the +97433123456 on the will. Retrying
  // only when the first parse was INVALID means countries that need the zero are never
  // touched: their first parse already succeeded.
  if (/^0\d/.test(candidate.trim())) {
    const retry = parsePhoneNumberFromString(candidate.trim().replace(/^0+/, ''), hint);
    if (retry?.isValid()) return retry.number;
  }

  // Parseable but NOT valid: deliberately fall through to plain digits rather than
  // returning parsed.number. libphonenumber will attach the hint's country code to
  // something that is not a real line in that plan — '0555000333' under REGION=US comes
  // back as a '+1…' string — and that invented prefix then compares unequal to the
  // genuine +966555000333 on the will, defeating the loose tier that would otherwise
  // have matched on the shared national digits. Degrading is safe; inventing is not.
  const digits = digitsOf(candidate);
  return candidate.trim().startsWith('+') ? `+${digits}` : digits;
}

/**
 * True when this number is Saudi.
 *
 * Exists for ONE decision: which channel a login code goes out on. A Saudi SMS costs
 * $0.1949 — 15.6x a US one, and the most expensive thing this product does per login —
 * while the same message over WhatsApp is roughly $0.045. So Saudi numbers are routed to
 * WhatsApp, where penetration is near-universal.
 *
 * Keyed on the NUMBER, not the user's region, because the bill follows the destination: a
 * KSA-region user carrying a US number is charged US rates, and a Saudi number belonging
 * to a US-region account is still a Saudi message.
 *
 * Asks libphonenumber for the country rather than matching a `+966` prefix, so a number
 * written in national form (`0555123456`) resolves correctly given the hint. Falls back to
 * the calling-code check only when the number is unparseable — where a prefix is the only
 * signal left, and a wrong answer merely picks the more expensive channel.
 */
export function isSaudiPhone(raw: string | null | undefined, regionHint?: string | null): boolean {
  const normalized = normalizePhone(raw, regionHint);
  if (!normalized) return false;
  const parsed = parsePhoneNumberFromString(normalized, countryHint(regionHint));
  if (parsed?.isValid()) return parsed.country === 'SA';
  return normalized.startsWith('+966');
}

/**
 * True when two numbers are the same line.
 *
 * Both sides are parsed to E.164 and compared exactly — per-country numbering plans do
 * the work that a fixed-length digit tail used to approximate. A national number and its
 * international spelling converge on the same E.164 string, so `0555123456` matches
 * `+966555123456` on a KSA deployment without any tail heuristic.
 *
 * The fallback tier is for numbers libphonenumber could not parse (partial entries, odd
 * legacy rows). It requires one side's digits to be a SUFFIX of the other's, plus a
 * minimum of 7 digits on the shorter side, so a truncated or short entry cannot collide
 * its way into a match. 7 is the shortest national subscriber length in real use; below
 * that we demand exact equality.
 */
export function phonesMatch(
  a: string | null | undefined,
  b: string | null | undefined,
  regionHint?: string | null,
): boolean {
  const na = normalizePhone(a, regionHint);
  const nb = normalizePhone(b, regionHint);
  if (!na || !nb) return false;
  if (na === nb) return true;

  // Both are VALID numbers and differ -> genuinely different lines, stop here.
  //
  // isValid(), not merely "parsed": libphonenumber will happily produce an E.164 for a
  // string that is not a real number in that plan. Qatar has no trunk prefix, so a
  // habitual '033123456' parses to something — and short-circuiting on that would
  // declare it a different line from '+97433123456' and skip the lenient tier below,
  // which is exactly the family-gets-rejected failure this file exists to prevent.
  const pa = parsePhoneNumberFromString(na, countryHint(regionHint));
  const pb = parsePhoneNumberFromString(nb, countryHint(regionHint));
  if (pa?.isValid() && pb?.isValid()) return pa.number === pb.number;

  const da = digitsOf(na);
  const db = digitsOf(nb);
  const [shortRaw, longer] = da.length <= db.length ? [da, db] : [db, da];

  // A leading trunk '0' has no meaning in E.164 and is the single most common thing a
  // person adds by habit — including in countries that have no trunk prefix at all
  // (Qatar). Trying the number without it costs nothing: the suffix check below still
  // has to match every remaining digit.
  const candidates = shortRaw.startsWith('0') ? [shortRaw, shortRaw.slice(1)] : [shortRaw];

  for (const shorter of candidates) {
    // 7 is the shortest national subscriber length in real use; below that we demand
    // exact equality, so a truncated or short entry cannot collide its way into a match.
    if (shorter.length < 7) continue;
    if (longer.endsWith(shorter)) return true;
  }
  return false;
}

/**
 * Plausible stored spellings of one number, for a `{ phone: { in: [...] } }` lookup
 * against a column we cannot run `phonesMatch` over in SQL.
 *
 * This is a PRE-FILTER, never the decision: whatever it returns is re-checked with
 * `phonesMatch` in JS. It exists so resolving a phone to a user is an indexed equality
 * lookup instead of a full-table scan. ESCALATION: a stored `phoneNormalized` column
 * would make this exact, and is the right fix once the user table is big enough for a
 * miss here to matter.
 */
export function phoneLookupVariants(raw: string | null | undefined, regionHint?: string | null): string[] {
  const normalized = normalizePhone(raw, regionHint);
  if (!normalized) return [];
  const digits = digitsOf(normalized);

  const variants = new Set<string>([String(raw ?? '').trim(), normalized, digits, `+${digits}`, `00${digits}`]);

  // Offer the national spellings too — libphonenumber knows this number's own country,
  // so this works for any country, not only the regions we deploy to.
  const parsed = parsePhoneNumberFromString(normalized, countryHint(regionHint));
  if (parsed?.nationalNumber) {
    const national = String(parsed.nationalNumber);
    variants.add(national);
    variants.add(`0${national}`);
    variants.add(parsed.formatNational().replace(/\s/g, ''));
  }

  return [...variants].filter(Boolean);
}
