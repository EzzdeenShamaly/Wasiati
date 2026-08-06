// Generates the ISO 3166-1 alpha-2 country table from Node's ICU, so the names are the
// real localized ones rather than hand-typed.
const fs = require('fs');

const en = new Intl.DisplayNames(['en'], { type: 'region' });
const ar = new Intl.DisplayNames(['ar'], { type: 'region' });

// ISO 3166-1 alpha-2: every AA..ZZ pair ICU recognises as a real region. This filters out
// the reserved/user-assigned ranges (ICU returns the code itself for those).
const codes = [];
for (let a = 65; a <= 90; a++) {
  for (let b = 65; b <= 90; b++) {
    const c = String.fromCharCode(a) + String.fromCharCode(b);
    const name = en.of(c);
    if (name && name !== c) codes.push(c);
  }
}

// Drop the supranational/aggregate entries ICU also answers for.
const drop = new Set(['EU', 'EZ', 'UN', 'QO', 'XA', 'XB', 'ZZ', 'AC', 'CP', 'DG', 'EA', 'IC', 'TA']);
const list = codes.filter((c) => !drop.has(c));

const rows = list
  .map((c) => `  Country('${c}', '${en.of(c).replace(/'/g, "\\'")}', '${ar.of(c).replace(/'/g, "\\'")}'),`)
  .join('\n');

const out = `// GENERATED — do not edit by hand.
//
// Regenerate with scripts/gen_countries.js, which reads the names out of ICU rather than
// transcribing them. Source: ISO 3166-1 alpha-2 via Intl.DisplayNames (en, ar).
//
// Why the full list: the sign-up country picker used to offer six countries — US, CA, SA,
// QA, AE, GB — because the list was written by hand next to the ADDRESS FORMAT rules, and
// those rules are only known for a handful. But the two are different questions. The
// backend has always accepted any ISO country (@IsISO31661Alpha2 on RegisterDto) and has
// always had a permissive address format for countries whose rules it does not know, so
// the client was narrower than the server for no reason. Wasiati sells globally; someone
// in Malaysia, Indonesia, Pakistan or Nigeria could not enter where they live.
//
// Address FORMAT rules stay a short hand-maintained list in address_rules.dart. That is
// correct: we only know the postcode and area conventions for a few places, and everyone
// else gets the permissive default.

/// One ISO 3166-1 alpha-2 country and its display name per supported locale.
class Country {
  const Country(this.code, this.en, this.ar);
  final String code;
  final String en;
  final String ar;

  /// The name for the active locale. Arabic for 'ar', English otherwise — the two
  /// locales the app ships.
  String nameFor(String languageCode) => languageCode == 'ar' ? ar : en;
}

/// Every ISO 3166-1 alpha-2 country, ${list.length} of them, ordered by code.
/// Sort for display with [countriesSortedFor], which orders by the localized name.
const kCountries = <Country>[
${rows}
];

/// The countries ordered by their name in [languageCode] — the order to show a human.
/// Code order is meaningless to a reader, and alphabetical-by-English is wrong in Arabic.
List<Country> countriesSortedFor(String languageCode) {
  final list = [...kCountries];
  list.sort((a, b) => a.nameFor(languageCode).compareTo(b.nameFor(languageCode)));
  return list;
}

/// Lookup by ISO code, or null when the code is not a country we know.
Country? countryFor(String code) {
  final upper = code.toUpperCase();
  for (final c in kCountries) {
    if (c.code == upper) return c;
  }
  return null;
}
`;

const dest = 'C:/Users/raed1/wasiati/app/apps/wasiati/lib/features/auth/domain/countries.dart';
fs.writeFileSync(dest, out);
console.log('wrote ' + list.length + ' countries to countries.dart');
