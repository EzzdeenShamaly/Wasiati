/// One zakatable category and the fiqh basis line shown beneath it.
class ZakatCategory {
  final String type; // CASH | BANK_ACCOUNT | SHARES | GOLD
  final int totalMinor;
  final String basisKey; // e.g. 'zakat.basis.cash'

  const ZakatCategory({required this.type, required this.totalMinor, required this.basisKey});

  factory ZakatCategory.fromJson(Map<String, dynamic> j) => ZakatCategory(
        type: j['type'] as String,
        totalMinor: (j['totalMinor'] as num).toInt(),
        basisKey: (j['basisKey'] as String?) ?? '',
      );
}

/// Holdings we could not value in the user's currency, because no fixed exchange
/// rate exists. They are shown, not silently dropped, and never converted at a
/// guessed rate.
class ZakatUnconverted {
  final String currency;
  final int totalMinor;
  final int count;
  const ZakatUnconverted({required this.currency, required this.totalMinor, required this.count});

  factory ZakatUnconverted.fromJson(Map<String, dynamic> j) => ZakatUnconverted(
        currency: j['currency'] as String,
        totalMinor: (j['totalMinor'] as num).toInt(),
        count: (j['count'] as num).toInt(),
      );
}

/// Ḥawl anniversary. Hijri only — never a Gregorian date.
class Hawl {
  final int day; // 1..30
  final int month; // 1..12
  const Hawl(this.day, this.month);
}

class ZakatEstimate {
  final String currency;
  final List<ZakatCategory> categories;
  final int excludedCryptoMinor;
  final List<ZakatUnconverted> unconverted;
  final int zakatableTotalMinor;
  final int nisabMinor;
  final bool aboveNisab;
  final int zakatDueMinor;
  final Hawl? hawl;

  /// Set only when an admin has published a vetted charity link. No link, no button.
  final String? charityUrl;

  const ZakatEstimate({
    required this.currency,
    required this.categories,
    required this.excludedCryptoMinor,
    required this.unconverted,
    required this.zakatableTotalMinor,
    required this.nisabMinor,
    required this.aboveNisab,
    required this.zakatDueMinor,
    required this.hawl,
    required this.charityUrl,
  });

  bool get hasExcludedCrypto => excludedCryptoMinor > 0;

  factory ZakatEstimate.fromJson(Map<String, dynamic> j) {
    final excluded = (j['excluded'] as List? ?? const [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((m) => m['type'] == 'CRYPTO')
        .fold<int>(0, (s, m) => s + ((m['totalMinor'] as num?)?.toInt() ?? 0));

    final hawlJson = j['hawl'] as Map?;

    return ZakatEstimate(
      currency: (j['currency'] as String?) ?? 'USD',
      categories: (j['categories'] as List? ?? const [])
          .cast<Map>()
          .map((m) => ZakatCategory.fromJson(m.cast<String, dynamic>()))
          .toList(),
      excludedCryptoMinor: excluded,
      unconverted: (j['unconverted'] as List? ?? const [])
          .cast<Map>()
          .map((m) => ZakatUnconverted.fromJson(m.cast<String, dynamic>()))
          .toList(),
      zakatableTotalMinor: (j['zakatableTotalMinor'] as num?)?.toInt() ?? 0,
      nisabMinor: (j['nisabMinor'] as num?)?.toInt() ?? 0,
      aboveNisab: (j['aboveNisab'] as bool?) ?? false,
      zakatDueMinor: (j['zakatDueMinor'] as num?)?.toInt() ?? 0,
      hawl: hawlJson == null
          ? null
          : Hawl((hawlJson['day'] as num).toInt(), (hawlJson['month'] as num).toInt()),
      charityUrl: j['charityUrl'] as String?,
    );
  }
}
