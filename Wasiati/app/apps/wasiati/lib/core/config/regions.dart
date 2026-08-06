// Region helpers shared across the app. Mirrors the backend's geo.util concepts so
// the UI gates match the server (which is always the authority).

/// Regions where a grave must be PAID for — burial pre-planning (the Ultimate tier)
/// is offered only here. Where burial is provided free (KSA, QA) there is nothing to
/// pre-pay, so Ultimate is shown as "not in your region". Keep in sync with the
/// backend's PAID_BURIAL_REGIONS.
const Set<String> kPaidBurialRegions = {'US', 'CA'};

/// True when a grave costs money in this region — the gate for Ultimate / burial planning.
bool regionRequiresPaidBurial(String region) => kPaidBurialRegions.contains(region);
