import { normalizePhone, phoneLookupVariants, phonesMatch } from './phone.util';

/**
 * The bug this file exists for: the death-claim path compared phones with
 * `p.replace(/[\s-]/g, '')`, so a family member who typed `0555123456` could never match
 * the `+966555123456` on the will — a first-attempt rejection on the one flow that has no
 * second chance.
 *
 * A will's contacts are not confined to the four regions we deploy to: a testator in
 * Riyadh may name a trustee in Cairo and a witness in Manchester. Matching therefore has
 * to be right for arbitrary countries, which is why this uses libphonenumber's
 * per-country numbering plans rather than a fixed-length digit tail.
 *
 * These tests pass `regionHint` EXPLICITLY. The previous suite leaned on ambient
 * process.env.REGION — which is 'US' in .env — so it asserted KSA behaviour while the
 * code parsed US numbers. See 'does NOT match numbers that merely share a digit tail':
 * that false positive is what those green tests were hiding.
 */
describe('normalizePhone', () => {
  it('canonicalises the spellings one person actually types', () => {
    expect(normalizePhone('  +966 555-123-456 ', 'KSA')).toBe('+966555123456');
    expect(normalizePhone('00966555123456', 'KSA')).toBe('+966555123456');
    expect(normalizePhone('0555123456', 'KSA')).toBe('+966555123456');
    expect(normalizePhone('+966555123456', 'KSA')).toBe('+966555123456');
  });

  it('accepts KSA or the ISO code SA for the same country', () => {
    expect(normalizePhone('0555123456', 'SA')).toBe(normalizePhone('0555123456', 'KSA'));
  });

  it('reads a number carrying its own country code without any hint', () => {
    expect(normalizePhone('+20 100 123 4567', 'KSA')).toBe('+201001234567');
    // NB: 07700 900xxx is Ofcom's reserved drama range and libphonenumber correctly
    // rejects it as unassignable, so test data must use a real range — 07911 is one.
    // That strictness is load-bearing here: it is the same isValid() check that stops a
    // bogus '+1…' being invented for a Saudi number under REGION=US.
    expect(normalizePhone('+44 7911 123456', 'US')).toBe('+447911123456');
    expect(normalizePhone('+81 90-1234-5678', 'CA')).toBe('+819012345678');
  });

  it('handles national form across countries of very different lengths', () => {
    // The point of the rewrite: no single tail length is correct across these.
    expect(normalizePhone('0555123456', 'SA')).toBe('+966555123456'); // 9-digit national
    expect(normalizePhone('33123456', 'QA')).toBe('+97433123456'); // 8-digit, no trunk 0
    expect(normalizePhone('(415) 555-2671', 'US')).toBe('+14155552671'); // 10-digit NANP
    expect(normalizePhone('07911 123456', 'GB')).toBe('+447911123456'); // trunk 0 + 10
    expect(normalizePhone('611 1234', 'IS')).toBe('+3546111234'); // Iceland: 7 digits
  });

  it('degrades instead of discarding when it cannot parse', () => {
    expect(normalizePhone('1234')).toBe('1234');
    expect(normalizePhone('not a phone')).toBe('');
    expect(normalizePhone('')).toBe('');
    expect(normalizePhone(null)).toBe('');
    expect(normalizePhone(undefined)).toBe('');
  });
});

describe('phonesMatch — the same line written differently', () => {
  it('matches national and international forms, both directions', () => {
    expect(phonesMatch('0555123456', '+966555123456', 'KSA')).toBe(true);
    expect(phonesMatch('+966555123456', '0555123456', 'KSA')).toBe(true);
    expect(phonesMatch('00966555123456', '0555123456', 'KSA')).toBe(true);
    expect(phonesMatch('+966 555 123 456', '0555-123-456', 'KSA')).toBe(true);
  });

  it("matches Qatar's 8-digit subscriber number across formats", () => {
    // Qatar is why a 9-digit tail was wrong — it reached into the country code.
    // Per-country plans remove the question rather than re-tuning the constant.
    expect(phonesMatch('+97433123456', '033123456', 'QA')).toBe(true);
    expect(phonesMatch('+974 3312 3456', '33123456', 'QA')).toBe(true);
  });

  it('matches short-national countries that a fixed tail REFUSED', () => {
    // The old fallback demanded >= 8 digits on both sides, so Iceland's 7-digit national
    // number could never match its own international form. This is the direction the
    // fixed tail failed silently: a real contact, declared not the same person.
    expect(phonesMatch('+3546111234', '611 1234', 'IS')).toBe(true);
    expect(phonesMatch('+4522334455', '22 33 44 55', 'DK')).toBe(true); // Denmark: 8
  });

  it('works for countries we do not deploy to', () => {
    expect(phonesMatch('+201001234567', '01001234567', 'EG')).toBe(true);
    expect(phonesMatch('+447911123456', '07911123456', 'GB')).toBe(true);
    expect(phonesMatch('+919876543210', '09876543210', 'IN')).toBe(true);
  });
});

describe('phonesMatch — genuinely different lines', () => {
  it('tells two numbers in the same country apart', () => {
    expect(phonesMatch('+97433123456', '+97433123457', 'QA')).toBe(false);
    expect(phonesMatch('+966555123456', '+966555123457', 'KSA')).toBe(false);
  });

  it('does NOT match numbers that merely share a digit tail across countries', () => {
    // THE REGRESSION THIS REWRITE EXISTS FOR. The fixed-tail comparison declared
    // +1555123456 (a US line) and +966555123456 (a KSA line) the same person, because
    // their last 8 digits coincide — and the previous suite asserted that as CORRECT, so
    // the false positive shipped green. On the claim path a false match means the wrong
    // person is treated as an authorised party on someone's estate.
    expect(phonesMatch('+1555123456', '+966555123456')).toBe(false);
    expect(phonesMatch('+14155552671', '+442015552671')).toBe(false);
  });

  it('refuses to match against an empty or unparseable value', () => {
    expect(phonesMatch('', '+966555123456')).toBe(false);
    expect(phonesMatch(null, null)).toBe(false);
    expect(phonesMatch('not a phone', 'not a phone')).toBe(false);
  });

  it('requires exact equality below 7 digits, so a short entry cannot collide', () => {
    expect(phonesMatch('1234', '5551234')).toBe(false);
    expect(phonesMatch('+1234', '+1234')).toBe(true);
  });
});

describe('phoneLookupVariants', () => {
  it('offers the spellings a number may be stored as', () => {
    const v = phoneLookupVariants('+966555123456', 'KSA');
    expect(v).toContain('+966555123456');
    expect(v).toContain('966555123456');
    expect(v).toContain('0555123456');
    expect(v).toContain('555123456');
  });

  it('derives national spellings for a foreign number too', () => {
    // Variants come from the number's OWN country, not the deployment region, so a
    // trustee abroad is still reachable by an indexed lookup.
    const v = phoneLookupVariants('+447911123456', 'KSA');
    expect(v).toContain('+447911123456');
    expect(v).toContain('7911123456');
    expect(v).toContain('07911123456');
  });

  it('is empty for nothing, and never contains an empty string', () => {
    expect(phoneLookupVariants('')).toEqual([]);
    expect(phoneLookupVariants(null)).toEqual([]);
    expect(phoneLookupVariants('+966555123456', 'KSA').every((s) => s.length > 0)).toBe(true);
  });

  it('is only a pre-filter — every variant it returns is the same line', () => {
    // Whatever this returns is re-checked with phonesMatch, so breadth is safe. What
    // would NOT be safe is returning a form belonging to a different number.
    for (const v of phoneLookupVariants('+97433123456', 'QA')) {
      expect(phonesMatch(v, '+97433123456', 'QA')).toBe(true);
    }
  });
});
