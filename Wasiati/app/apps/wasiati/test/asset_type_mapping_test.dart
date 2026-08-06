import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/assets/domain/asset_models.dart';

/// The zakat estimator reads the backend AssetType. If the client records gold as
/// OTHER, or crypto as OTHER, the estimate is silently wrong: gold vanishes from the
/// base, and crypto sneaks in as an unclassified holding it can no longer exclude.
void main() {
  test('zakat-relevant kinds map to their own backend types, not OTHER', () {
    expect(assetTypeFromKind('CASH'), 'CASH');
    expect(assetTypeFromKind('SHARES'), 'SHARES');
    expect(assetTypeFromKind('GOLD'), 'GOLD');
    expect(assetTypeFromKind('CRYPTO'), 'CRYPTO');
  });

  test('backend types round-trip back to the same UI kind', () {
    for (final k in ['CASH', 'SHARES', 'GOLD', 'CRYPTO', 'REAL_ESTATE', 'VEHICLE', 'LIABILITY']) {
      expect(assetKindFromType(assetTypeFromKind(k)), k, reason: 'round trip for $k');
    }
  });

  test('CRYPTO stays distinct — it must never collapse into OTHER', () {
    expect(assetKindFromType('CRYPTO'), 'CRYPTO');
    expect(assetKindFromType('CRYPTO'), isNot('OTHER'));
  });

  test('an unknown backend type still degrades to OTHER', () {
    expect(assetKindFromType('SOMETHING_NEW'), 'OTHER');
  });

  test('bank-like registered accounts still map to BANK, and pensions to PENSION', () {
    expect(assetKindFromType('CA_TFSA'), 'BANK');
    expect(assetKindFromType('QA_GRSIA_PENSION'), 'PENSION');
    expect(assetKindFromType('KSA_GOSI_PENSION'), 'PENSION');
  });
}
