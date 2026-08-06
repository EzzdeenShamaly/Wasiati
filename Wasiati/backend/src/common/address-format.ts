/**
 * Per-country postal address rules.
 *
 * Address formats differ by country in three ways that matter to a form and to a printed
 * legal document: which fields are REQUIRED, what the administrative area is CALLED
 * ("state", "province", "emirate"), and whether a postal code exists at all. Validating one
 * shape everywhere rejects valid addresses — Qatar has no postal codes, so a required
 * postcode locks out an entire market; the US and Canada would accept a blank one.
 *
 * The canonical open dataset for this is Google's libaddressinput (what Chrome and Android
 * autofill use). It is deliberately NOT vendored here: it carries ~250 countries with
 * localised sublocality rules and its own update cadence, and this product sells in four
 * markets. Embedding a megabyte of metadata to serve four rows, and taking on the job of
 * keeping it fresh, would be the expensive kind of thorough. The table below covers the
 * markets we sell in, with a permissive default for everyone else — a customer in one of our
 * markets may well live somewhere we do not sell, and their address must still be accepted.
 *
 * If the market list grows past a handful, replace this table with libaddressinput rather
 * than extending it by hand.
 *
 * `areaLabelKey` is an l10n KEY, not display text: the label has to render in Arabic too,
 * and the server has no business choosing the user's language.
 */
export interface AddressRules {
  /** ISO 3166-1 alpha-2. */
  country: string;
  /** Fields the user must supply, beyond line 1 + city which every country needs. */
  requires: ReadonlyArray<'area' | 'postalCode'>;
  /** l10n key for what this country calls the administrative area, if it uses one. */
  areaLabelKey?: 'addrState' | 'addrProvince' | 'addrEmirate' | 'addrRegion';
  /** Anchored postal-code pattern, when the country has one worth checking. */
  postalPattern?: RegExp;
}

const RULES: Readonly<Record<string, AddressRules>> = {
  // Saudi Arabia — Short National Address exists but plenty of residents cannot recite it;
  // the 5-digit postcode is real but optional in practice, so it is checked only if given.
  SA: { country: 'SA', requires: ['area'], areaLabelKey: 'addrRegion', postalPattern: /^\d{5}$/ },
  // Qatar has NO postal codes at all, and no administrative area in everyday addressing
  // (zone / street / building numbers carry it). Requiring either would lock out the market.
  QA: { country: 'QA', requires: [] },
  US: { country: 'US', requires: ['area', 'postalCode'], areaLabelKey: 'addrState', postalPattern: /^\d{5}(-\d{4})?$/ },
  // Canadian postcodes exclude D, F, I, O, Q and U to avoid OCR confusion.
  CA: {
    country: 'CA',
    requires: ['area', 'postalCode'],
    areaLabelKey: 'addrProvince',
    postalPattern: /^[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d$/i,
  },
  AE: { country: 'AE', requires: ['area'], areaLabelKey: 'addrEmirate' },
  GB: { country: 'GB', requires: ['postalCode'], areaLabelKey: 'addrRegion' },
};

/** Permissive fallback: line 1 + city only. We do not know this country's rules, and a
 *  guessed rule that rejects a real address is worse than no rule. */
const DEFAULT_RULES: AddressRules = { country: '??', requires: [] };

export function addressRulesFor(country: string): AddressRules {
  return RULES[(country ?? '').toUpperCase()] ?? { ...DEFAULT_RULES, country: (country ?? '').toUpperCase() };
}

export interface AddressInput {
  addressLine1?: string | null;
  addressCity?: string | null;
  addressArea?: string | null;
  addressPostalCode?: string | null;
  addressCountry?: string | null;
}

/**
 * Returns the field names that are missing or malformed, empty when the address is usable.
 * Field names match the DTO so the client can attach each message to its own input.
 */
export function validateAddress(input: AddressInput): string[] {
  const errors: string[] = [];
  const country = (input.addressCountry ?? '').toUpperCase();
  if (!country || country.length !== 2) errors.push('addressCountry');

  if (!input.addressLine1?.trim()) errors.push('addressLine1');
  if (!input.addressCity?.trim()) errors.push('addressCity');

  const rules = addressRulesFor(country);
  if (rules.requires.includes('area') && !input.addressArea?.trim()) errors.push('addressArea');

  const postal = input.addressPostalCode?.trim();
  if (rules.requires.includes('postalCode') && !postal) {
    errors.push('addressPostalCode');
  } else if (postal && rules.postalPattern && !rules.postalPattern.test(postal)) {
    // Only when one was supplied: an optional-but-wrong postcode is still wrong.
    errors.push('addressPostalCode');
  }
  return errors;
}
