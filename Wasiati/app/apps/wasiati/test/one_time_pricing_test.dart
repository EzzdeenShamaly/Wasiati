import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/commerce/data/commerce_api.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';

/// The one-time cycle (owner punch-list #2):
///   · each tier shows a SINGLE price — no "/mo", no "/yr";
///   · Ultimate is not on it at all — its burial contributions are inherently
///     recurring, so there is no coherent one-time version to sell.
///
/// The rule lives on the backend (commerce/plan-rules.ts) and rides to the client
/// on `purchasable`; these pin the client half of it.
PricingPlan plan({
  required String tier,
  required String interval,
  bool purchasable = true,
  int unitAmount = 9900,
  String currency = 'USD',
}) =>
    PricingPlan.fromJson({
      'id': '$tier-$interval',
      'tier': tier,
      'region': 'US',
      'currency': currency,
      'unitAmount': unitAmount,
      'interval': interval,
      'displayName': tier,
      'features': const <String>[],
      'sortOrder': 1,
      'active': true,
      'purchasable': purchasable,
    });

/// Mirrors the pricing screen's grid filter: only buyable plans on this cycle.
List<PricingPlan> visibleOn(String cycle, List<PricingPlan> all) =>
    all.where((p) => p.interval == cycle && p.purchasable).toList();

void main() {
  group('one-time cycle shows a single price', () {
    test('a one-time plan carries no cadence suffix', () {
      final p = plan(tier: 'STANDARD', interval: 'ONE_TIME', unitAmount: 9900);
      expect(p.isOneTime, isTrue);
      // The card renders `priceLabel` alone when isOneTime — one number, nothing
      // that suggests it recurs.
      expect(p.priceLabel, '\$99.00');
    });

    test('recurring plans still say which cadence they are', () {
      expect(plan(tier: 'STANDARD', interval: 'MONTH').isOneTime, isFalse);
      expect(plan(tier: 'STANDARD', interval: 'YEAR').isOneTime, isFalse);
    });
  });

  group('Ultimate is not purchasable one-time', () {
    test('an unpurchasable Ultimate one-time row is filtered out of the grid', () {
      final all = [
        plan(tier: 'STANDARD', interval: 'ONE_TIME'),
        plan(tier: 'PREMIUM', interval: 'ONE_TIME'),
        // What the catalog returns if an admin hand-creates the row.
        plan(tier: 'ULTIMATE', interval: 'ONE_TIME', purchasable: false),
      ];
      final shown = visibleOn('ONE_TIME', all).map((p) => p.tier);
      expect(shown, ['STANDARD', 'PREMIUM']);
      expect(shown, isNot(contains('ULTIMATE')));
    });

    test('Ultimate stays on the recurring cycles', () {
      final all = [
        plan(tier: 'ULTIMATE', interval: 'MONTH'),
        plan(tier: 'ULTIMATE', interval: 'YEAR'),
        plan(tier: 'ULTIMATE', interval: 'ONE_TIME', purchasable: false),
      ];
      expect(visibleOn('MONTH', all).map((p) => p.tier), ['ULTIMATE']);
      expect(visibleOn('YEAR', all).map((p) => p.tier), ['ULTIMATE']);
      expect(visibleOn('ONE_TIME', all), isEmpty);
    });

    test('the explanatory note fires only on the one-time cycle of an Ultimate region', () {
      // Mirrors the screen's `ultimateHidden`.
      bool noteFor(String cycle, List<PricingPlan> all) =>
          cycle == 'ONE_TIME' &&
          all.any((p) => p.tier == 'ULTIMATE') &&
          !visibleOn(cycle, all).any((p) => p.tier == 'ULTIMATE');

      final withUltimate = [
        plan(tier: 'STANDARD', interval: 'ONE_TIME'),
        plan(tier: 'ULTIMATE', interval: 'MONTH'),
      ];
      expect(noteFor('ONE_TIME', withUltimate), isTrue, reason: 'Ultimate exists but is absent from this cycle');
      expect(noteFor('MONTH', withUltimate), isFalse, reason: 'Ultimate is right there on the monthly cycle');

      // A free-burial region (KSA/QA) has no Ultimate at all — that absence is
      // explained by prNoUltimateNote instead, so this note must stay quiet.
      final noUltimate = [plan(tier: 'STANDARD', interval: 'ONE_TIME')];
      expect(noteFor('ONE_TIME', noUltimate), isFalse);
    });

    test('purchasable defaults TRUE when the field is absent, so nothing is hidden by surprise', () {
      final p = PricingPlan.fromJson({
        'id': 'x',
        'tier': 'STANDARD',
        'region': 'US',
        'currency': 'USD',
        'unitAmount': 900,
        'interval': 'MONTH',
        'displayName': 'Standard',
        'features': const <String>[],
        'sortOrder': 1,
        'active': true,
      });
      expect(p.purchasable, isTrue);
    });
  });

  group('against the live backend', () {
    test('the US catalog offers no Ultimate one-time plan', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000', contentType: Headers.jsonContentType));
      try {
        final cat = await CommerceApi(dio).catalog('US');
        final once = cat.plans.where((p) => p.interval == 'ONE_TIME').toList();
        expect(once, isNotEmpty, reason: 'the software tiers are still sold one-time');
        expect(once.map((p) => p.tier), isNot(contains('ULTIMATE')));
        // …and Ultimate is still sold as a subscription.
        expect(cat.plans.where((p) => p.tier == 'ULTIMATE' && p.interval != 'ONE_TIME'), isNotEmpty);
      } on ApiException catch (e) {
        skipIfBackendDown(e);
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
