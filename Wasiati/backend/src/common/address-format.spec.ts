import { addressRulesFor, validateAddress } from './address-format';

/**
 * Address validation is per-country because a single shape rejects real addresses. The two
 * failures that matter commercially are both here: requiring a postal code in Qatar (which
 * has none) locks out an entire market, and accepting a blank one in the US or Canada lets
 * an unusable address into a legal document.
 */
describe('per-country address rules', () => {
  const base = { addressLine1: '12 Palm St', addressCity: 'Doha', addressCountry: 'QA' };

  it('accepts a Qatari address with no postal code and no area', () => {
    expect(validateAddress(base)).toEqual([]);
  });

  it('does NOT invent a postal-code requirement for Qatar', () => {
    expect(addressRulesFor('QA').requires).not.toContain('postalCode');
  });

  it('requires state AND ZIP in the US', () => {
    const errs = validateAddress({ addressLine1: '1 Main St', addressCity: 'Austin', addressCountry: 'US' });
    expect(errs).toEqual(expect.arrayContaining(['addressArea', 'addressPostalCode']));
  });

  it('accepts a complete US address, ZIP+4 included', () => {
    const ok = { addressLine1: '1 Main St', addressCity: 'Austin', addressArea: 'TX', addressCountry: 'US' };
    expect(validateAddress({ ...ok, addressPostalCode: '78701' })).toEqual([]);
    expect(validateAddress({ ...ok, addressPostalCode: '78701-1234' })).toEqual([]);
  });

  it('rejects a malformed US ZIP', () => {
    const errs = validateAddress({
      addressLine1: '1 Main St',
      addressCity: 'Austin',
      addressArea: 'TX',
      addressPostalCode: 'ABCDE',
      addressCountry: 'US',
    });
    expect(errs).toContain('addressPostalCode');
  });

  it('accepts a Canadian postcode with or without the space, either case', () => {
    const ca = (postal: string) =>
      validateAddress({
        addressLine1: '5 King St',
        addressCity: 'Toronto',
        addressArea: 'ON',
        addressPostalCode: postal,
        addressCountry: 'CA',
      });
    expect(ca('M5H 2N2')).toEqual([]);
    expect(ca('M5H2N2')).toEqual([]);
    expect(ca('m5h 2n2')).toEqual([]);
  });

  it('rejects a Canadian postcode using an excluded letter', () => {
    // D, F, I, O, Q, U are omitted from Canadian postcodes to avoid OCR confusion.
    expect(
      validateAddress({
        addressLine1: '5 King St',
        addressCity: 'Toronto',
        addressArea: 'ON',
        addressPostalCode: 'D5H 2N2',
        addressCountry: 'CA',
      }),
    ).toContain('addressPostalCode');
  });

  it('treats the Saudi postcode as optional but still checks one that IS given', () => {
    const sa = (postal?: string) =>
      validateAddress({
        addressLine1: 'King Fahd Rd',
        addressCity: 'Riyadh',
        addressArea: 'Riyadh Province',
        addressPostalCode: postal,
        addressCountry: 'SA',
      });
    expect(sa()).toEqual([]);
    expect(sa('12345')).toEqual([]);
    expect(sa('12')).toContain('addressPostalCode');
  });

  it('requires the area in Saudi Arabia', () => {
    expect(
      validateAddress({ addressLine1: 'King Fahd Rd', addressCity: 'Riyadh', addressCountry: 'SA' }),
    ).toContain('addressArea');
  });

  it('falls back to line1 + city for a country we have no rules for', () => {
    // A customer in one of our markets may live somewhere we do not sell. Guessing a rule
    // and rejecting their real address would be worse than having no rule.
    expect(validateAddress({ addressLine1: '3 Rua X', addressCity: 'Lisboa', addressCountry: 'PT' })).toEqual([]);
    expect(validateAddress({ addressLine1: '', addressCity: 'Lisboa', addressCountry: 'PT' })).toContain('addressLine1');
  });

  it('always demands line 1, city and a 2-letter country', () => {
    const errs = validateAddress({});
    expect(errs).toEqual(expect.arrayContaining(['addressCountry', 'addressLine1', 'addressCity']));
  });

  it('is case-insensitive about the country code', () => {
    expect(addressRulesFor('us').requires).toContain('postalCode');
  });

  it('names the administrative area the way each country does', () => {
    expect(addressRulesFor('US').areaLabelKey).toBe('addrState');
    expect(addressRulesFor('CA').areaLabelKey).toBe('addrProvince');
    expect(addressRulesFor('AE').areaLabelKey).toBe('addrEmirate');
    expect(addressRulesFor('SA').areaLabelKey).toBe('addrRegion');
  });
});
