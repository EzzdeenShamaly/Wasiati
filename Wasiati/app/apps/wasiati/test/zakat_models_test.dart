import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/zakat/domain/zakat_models.dart';

Map<String, dynamic> payload([Map<String, dynamic> over = const {}]) => {
      'currency': 'SAR',
      'categories': [
        {'type': 'CASH', 'totalMinor': 5000000, 'basisKey': 'zakat.basis.cash'},
        {'type': 'GOLD', 'totalMinor': 1000000, 'basisKey': 'zakat.basis.gold'},
      ],
      'excluded': [
        {'type': 'CRYPTO', 'totalMinor': 99900000, 'currency': 'SAR', 'reasonKey': 'zakat.excluded.crypto'},
      ],
      'unconverted': [
        {'currency': 'CAD', 'totalMinor': 250000, 'count': 2},
      ],
      'zakatableTotalMinor': 6000000,
      'nisabMinor': 4250000,
      'aboveNisab': true,
      'zakatDueMinor': 150000,
      'rateBp': 250,
      'hawl': {'day': 15, 'month': 9},
      'charityUrl': 'https://charity.example',
      'isEstimate': true,
      ...over,
    };

void main() {
  test('parses categories with their fiqh basis keys', () {
    final z = ZakatEstimate.fromJson(payload());
    expect(z.categories.map((c) => c.type), ['CASH', 'GOLD']);
    expect(z.categories.first.basisKey, 'zakat.basis.cash');
    expect(z.zakatDueMinor, 150000);
    expect(z.aboveNisab, isTrue);
  });

  test('surfaces excluded crypto so the UI can disclose it', () {
    final z = ZakatEstimate.fromJson(payload());
    expect(z.hasExcludedCrypto, isTrue);
    expect(z.excludedCryptoMinor, 99900000);
    // Crypto must never be folded into the zakatable total.
    expect(z.zakatableTotalMinor, 6000000);
  });

  test('reports holdings that could not be converted, rather than dropping them', () {
    final z = ZakatEstimate.fromJson(payload());
    expect(z.unconverted, hasLength(1));
    expect(z.unconverted.first.currency, 'CAD');
    expect(z.unconverted.first.count, 2);
  });

  test('no crypto means nothing to disclose', () {
    final z = ZakatEstimate.fromJson(payload({'excluded': <Map<String, dynamic>>[]}));
    expect(z.hasExcludedCrypto, isFalse);
    expect(z.excludedCryptoMinor, 0);
  });

  test('parses the Hijri hawl, and tolerates it being unset', () {
    expect(ZakatEstimate.fromJson(payload()).hawl!.day, 15);
    expect(ZakatEstimate.fromJson(payload()).hawl!.month, 9);
    expect(ZakatEstimate.fromJson(payload({'hawl': null})).hawl, isNull);
  });

  test('a null charity link means no "Pay your zakah" button can render', () {
    expect(ZakatEstimate.fromJson(payload({'charityUrl': null})).charityUrl, isNull);
    expect(ZakatEstimate.fromJson(payload()).charityUrl, 'https://charity.example');
  });

  test('below nisab, nothing is due', () {
    final z = ZakatEstimate.fromJson(payload({
      'aboveNisab': false,
      'zakatDueMinor': 0,
      'zakatableTotalMinor': 100000,
    }));
    expect(z.aboveNisab, isFalse);
    expect(z.zakatDueMinor, 0);
  });

  test('missing lists parse as empty rather than crashing the screen', () {
    final z = ZakatEstimate.fromJson({
      'currency': 'USD',
      'zakatableTotalMinor': 0,
      'nisabMinor': 0,
      'aboveNisab': false,
      'zakatDueMinor': 0,
    });
    expect(z.categories, isEmpty);
    expect(z.unconverted, isEmpty);
    expect(z.hasExcludedCrypto, isFalse);
  });
}
