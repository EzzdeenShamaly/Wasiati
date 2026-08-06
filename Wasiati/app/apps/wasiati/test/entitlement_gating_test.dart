import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/commerce/application/entitlement_providers.dart';

/// The will-start chooser and every feature CTA gate on these flags. Getting the
/// default wrong (offering AI to a Standard user) means a guaranteed 403; getting it
/// too strict hides a paid feature. So the resolver's edge cases are pinned here.
void main() {
  group('entitlementHas', () {
    test('reads a true feature flag', () {
      final ent = {
        'tier': 'PREMIUM',
        'features': {'aiIntake': true, 'videoMessages': true},
      };
      expect(entitlementHas(ent, 'aiIntake'), isTrue);
      expect(entitlementHas(ent, 'videoMessages'), isTrue);
    });

    test('reads a false feature flag', () {
      final ent = {
        'tier': 'STANDARD',
        'features': {'aiIntake': false, 'videoMessages': false},
      };
      expect(entitlementHas(ent, 'aiIntake'), isFalse);
    });

    test('defaults to FALSE when entitlement is null (loading/error) — shows soft-sell, never a 403', () {
      expect(entitlementHas(null, 'aiIntake'), isFalse);
    });

    test('defaults to false for an unknown feature or a missing features map', () {
      expect(entitlementHas({'tier': 'PREMIUM'}, 'aiIntake'), isFalse);
      expect(entitlementHas({'features': {'aiIntake': true}}, 'somethingElse'), isFalse);
    });

    test('treats a non-boolean flag value as false (defensive)', () {
      expect(entitlementHas({'features': {'aiIntake': 'yes'}}, 'aiIntake'), isFalse);
      expect(entitlementHas({'features': {'aiIntake': 1}}, 'aiIntake'), isFalse);
    });
  });
}

