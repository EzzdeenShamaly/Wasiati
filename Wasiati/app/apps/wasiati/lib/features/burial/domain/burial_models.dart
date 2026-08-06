class BurialEstimate {
  final String id;
  final String city;
  final String currency;
  final double baseAmount;
  final double projectedAmount;
  final double inflationRatePercent;
  final int projectionYears;
  final int baseYear;
  final String status; // ESTIMATED | QUOTE_REQUESTED | QUOTED | CONFIRMED | CANCELLED
  final double? manualQuoteAmount;
  final String? manualQuoteNotes;

  const BurialEstimate({
    required this.id,
    required this.city,
    required this.currency,
    required this.baseAmount,
    required this.projectedAmount,
    required this.inflationRatePercent,
    required this.projectionYears,
    required this.baseYear,
    required this.status,
    this.manualQuoteAmount,
    this.manualQuoteNotes,
  });

  static double _d(dynamic v) => double.tryParse('$v') ?? 0;

  factory BurialEstimate.fromJson(Map<String, dynamic> j) => BurialEstimate(
        id: j['id'] as String,
        city: j['city'] as String,
        currency: j['currency'] as String,
        baseAmount: _d(j['baseAmount']),
        projectedAmount: _d(j['projectedAmount']),
        inflationRatePercent: _d(j['inflationRatePercent']),
        projectionYears: (j['projectionYears'] as num?)?.toInt() ?? 10,
        baseYear: (j['baseYear'] as num?)?.toInt() ?? 0,
        status: j['status'] as String,
        manualQuoteAmount: j['manualQuoteAmount'] == null ? null : _d(j['manualQuoteAmount']),
        manualQuoteNotes: j['manualQuoteNotes'] as String?,
      );

  String money(double v) => currency == 'CAD' ? 'CA\$${v.toStringAsFixed(0)}' : '\$${v.toStringAsFixed(0)}';
}

/// One row of the ADMIN quote queue (GET /admin/burial-estimates/pending): the
/// estimate plus who asked — the admin has to phone mosques in the requester's
/// city and then tell them, so a queue without contact details is unanswerable.
class BurialQuoteRequest {
  final BurialEstimate estimate;
  final String userEmail;
  final String? userPhone;
  final String userRegion;
  final DateTime? createdAt;

  const BurialQuoteRequest({
    required this.estimate,
    required this.userEmail,
    required this.userRegion,
    this.userPhone,
    this.createdAt,
  });

  factory BurialQuoteRequest.fromJson(Map<String, dynamic> j) {
    final user = ((j['user'] as Map?) ?? const {}).cast<String, dynamic>();
    return BurialQuoteRequest(
      estimate: BurialEstimate.fromJson(j),
      userEmail: user['email'] as String? ?? '',
      userPhone: user['phone'] as String?,
      userRegion: user['region'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    );
  }
}
