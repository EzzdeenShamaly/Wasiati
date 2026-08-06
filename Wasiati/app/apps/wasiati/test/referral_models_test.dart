import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/referrals/domain/referral_models.dart';

Map<String, dynamic> payload([Map<String, dynamic> over = const {}]) => {
      'code': 'ABCD2345',
      'shareUrl': 'https://app.wasiati.com/register?ref=ABCD2345',
      'invited': 3,
      'qualified': 1,
      'rewarded': 2,
      'capped': 0,
      'currency': 'SAR',
      'earnedThisYearMinor': 4000,
      'yearlyCapMinor': 187500,
      'remainingThisYearMinor': 183500,
      'creditSpendableMinor': 1000,
      'creditHeldMinor': 3000,
      'holdDays': 100,
      'friendDiscountPercent': 10,
      ...over,
    };

void main() {
  test('parses the summary and keeps spendable and held credit apart', () {
    final s = ReferralSummary.fromJson(payload());
    expect(s.code, 'ABCD2345');
    expect(s.currency, 'SAR');
    // These must never be conflated: held credit cannot be spent yet.
    expect(s.creditSpendableMinor, 1000);
    expect(s.creditHeldMinor, 3000);
    expect(s.holdDays, 100);
    expect(s.friendDiscountPercent, 10);
  });

  test('capReached is false while headroom remains', () {
    expect(ReferralSummary.fromJson(payload()).capReached, isFalse);
  });

  test('capReached is true once the yearly ceiling is exhausted', () {
    final s = ReferralSummary.fromJson(payload({'remainingThisYearMinor': 0}));
    expect(s.capReached, isTrue);
  });

  test('a missing numeric field reads as zero rather than throwing', () {
    // A field the server has not shipped yet must not crash the screen.
    final s = ReferralSummary.fromJson(payload({'creditHeldMinor': null, 'capped': null}));
    expect(s.creditHeldMinor, 0);
    expect(s.capped, 0);
  });

  test('falls back to USD when the server sends no currency', () {
    final s = ReferralSummary.fromJson(payload({'currency': null}));
    expect(s.currency, 'USD');
  });
}
