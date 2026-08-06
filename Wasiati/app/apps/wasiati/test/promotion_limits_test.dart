import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';

/// The admin console shows WHY a code is or isn't working. The server is the
/// authority (PromotionsService.validate); these guard the client mirror so the
/// chip never claims "Live" for a code checkout would refuse.
Promotion _promo({
  int timesRedeemed = 0,
  int? maxRedemptions,
  bool firstTimeOnly = false,
  DateTime? startsAt,
  DateTime? endsAt,
  bool active = true,
}) =>
    Promotion(
      id: 'p1',
      code: 'WASIATI30',
      type: 'PERCENT',
      value: 30,
      active: active,
      timesRedeemed: timesRedeemed,
      maxRedemptions: maxRedemptions,
      firstTimeOnly: firstTimeOnly,
      startsAt: startsAt,
      endsAt: endsAt,
    );

void main() {
  final now = DateTime.utc(2026, 7, 17, 12);
  final past = DateTime.utc(2026, 7, 1);
  final future = DateTime.utc(2026, 8, 1);

  group('redemption cap', () {
    test('uncapped never exhausts', () {
      expect(_promo(timesRedeemed: 999_999).isExhausted, isFalse);
    });

    test('under the cap is not exhausted', () {
      expect(_promo(timesRedeemed: 99, maxRedemptions: 100).isExhausted, isFalse);
    });

    test('exhausts AT the cap, not one past it', () {
      // The server rejects on `timesRedeemed >= maxRedemptions`. An off-by-one
      // here would let the 101st signup see "Live" on a 100-signup code.
      expect(_promo(timesRedeemed: 100, maxRedemptions: 100).isExhausted, isTrue);
    });

    test('a cap of 1 is single-use', () {
      expect(_promo(maxRedemptions: 1).isExhausted, isFalse);
      expect(_promo(timesRedeemed: 1, maxRedemptions: 1).isExhausted, isTrue);
    });
  });

  group('date window', () {
    test('no window = always open', () {
      final p = _promo();
      expect(p.isExpiredAt(now), isFalse);
      expect(p.isScheduledAt(now), isFalse);
    });

    test('future start is scheduled, not live', () {
      expect(_promo(startsAt: future).isScheduledAt(now), isTrue);
      expect(_promo(startsAt: future).isLiveAt(now), isFalse);
    });

    test('past end is expired', () {
      expect(_promo(endsAt: past).isExpiredAt(now), isTrue);
      expect(_promo(endsAt: past).isLiveAt(now), isFalse);
    });

    test('inside the window is live', () {
      expect(_promo(startsAt: past, endsAt: future).isLiveAt(now), isTrue);
    });

    test('boundaries are inclusive — a code ending today still works today', () {
      // The dialog stamps end-dates at 23:59:59 precisely so "ends 17 Jul" does
      // not expire at midnight as the day begins.
      final endOfToday = DateTime.utc(2026, 7, 17, 23, 59, 59);
      expect(_promo(endsAt: endOfToday).isExpiredAt(now), isFalse);
      expect(_promo(startsAt: now).isScheduledAt(now), isFalse);
    });
  });

  group('isLiveAt combines every gate', () {
    test('inactive beats everything', () {
      expect(_promo(active: false, startsAt: past, endsAt: future).isLiveAt(now), isFalse);
    });

    test('exhausted inside a valid window is still not live', () {
      expect(
        _promo(timesRedeemed: 5, maxRedemptions: 5, startsAt: past, endsAt: future).isLiveAt(now),
        isFalse,
      );
    });

    test('unconstrained active code is live', () {
      expect(_promo().isLiveAt(now), isTrue);
    });
  });

  group('fromJson', () {
    test('parses the limit fields the admin form writes', () {
      final p = Promotion.fromJson({
        'id': 'p1',
        'code': 'WASIATI30',
        'type': 'PERCENT',
        'value': 30,
        'active': true,
        'timesRedeemed': 3,
        'maxRedemptions': 100,
        'firstTimeOnly': true,
        'startsAt': '2026-07-01T00:00:00.000Z',
        'endsAt': '2026-08-01T23:59:59.000Z',
      });
      expect(p.maxRedemptions, 100);
      expect(p.firstTimeOnly, isTrue);
      expect(p.startsAt, DateTime.utc(2026, 7, 1));
      expect(p.endsAt, DateTime.utc(2026, 8, 1, 23, 59, 59));
      expect(p.isLiveAt(now), isTrue);
    });

    test('an uncapped, open-ended code parses to nulls not zeros', () {
      // A 0 cap would read as "exhausted immediately" — the old model dropped
      // these fields entirely, so absence must stay absence.
      final p = Promotion.fromJson({
        'id': 'p1',
        'code': 'FREE',
        'type': 'PERCENT',
        'value': 10,
        'active': true,
        'timesRedeemed': 0,
      });
      expect(p.maxRedemptions, isNull);
      expect(p.startsAt, isNull);
      expect(p.endsAt, isNull);
      expect(p.firstTimeOnly, isFalse);
      expect(p.isExhausted, isFalse);
      expect(p.isLiveAt(now), isTrue);
    });

    test('explicit nulls from the API do not crash the parser', () {
      final p = Promotion.fromJson({
        'id': 'p1',
        'code': 'FREE',
        'type': 'PERCENT',
        'value': 10,
        'active': true,
        'timesRedeemed': 0,
        'maxRedemptions': null,
        'startsAt': null,
        'endsAt': null,
        'firstTimeOnly': null,
      });
      expect(p.maxRedemptions, isNull);
      expect(p.startsAt, isNull);
      expect(p.firstTimeOnly, isFalse);
    });
  });
}
