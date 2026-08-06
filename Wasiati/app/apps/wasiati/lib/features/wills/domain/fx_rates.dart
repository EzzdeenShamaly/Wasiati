// Fixed demo FX rates + local-currency helpers for the create-flow estate card
// (spec §3 step 2: "foreign amounts converted to local currency at today's rate
// with FX note"). Production pulls live rates; totals always show in the user's
// local currency (spec §8: User.localCurrency from region).

/// Units of currency per 1 USD — ported VERBATIM from the prototype's fromUSD():
///   const fx = { USD: 1, SAR: 3.75, AED: 3.67, KWD: 0.307, EUR: 0.92, GBP: 0.79, CAD: 1.36 };
/// QAR (3.64 peg) is retained for FX conversion only — an owner may hold assets in QAR
/// prototype's KSA-only demo data never exercised.
const Map<String, double> kFxPerUsd = {
  'USD': 1,
  'SAR': 3.75,
  'AED': 3.67,
  'KWD': 0.307,
  'EUR': 0.92,
  'GBP': 0.79,
  'CAD': 1.36,
  'QAR': 3.64,
};

/// The prototype's fromUSD(): a USD amount in [cur], rounded to the unit.
int fromUsd(num usd, String cur) => (usd * (kFxPerUsd[cur] ?? 1)).round();

/// Converts [amt] recorded in [cur] into the user's [local] currency through the
/// USD peg. A currency missing from the table passes through unchanged — the
/// prototype's `fx[cur] || 1` behaviour — so totals never silently drop a row.
double toLocal(num amt, String cur, String local) {
  if (cur == local) return amt.toDouble();
  final from = kFxPerUsd[cur];
  final to = kFxPerUsd[local] ?? 1;
  if (from == null) return amt.toDouble();
  return amt / from * to;
}

/// The region's own currency (spec §8: localCurrency(from region)).
String localCurrencyForRegion(String region) => switch (region) {
      'KSA' => 'SAR',
      'CA' => 'CAD',
      _ => 'USD',
    };
