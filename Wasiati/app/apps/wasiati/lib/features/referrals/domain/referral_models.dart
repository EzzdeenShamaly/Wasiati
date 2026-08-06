/// A user's referral standing, as returned by `GET /referrals/me`.
///
/// Money is in MINOR units of [currency]. Two credit figures matter and must not be
/// conflated: [creditSpendableMinor] can be used at checkout today, while
/// [creditHeldMinor] is commission still inside its [holdDays] window — earned and
/// visible, but not yet spendable.
class ReferralSummary {
  final String code;
  final String shareUrl;
  final int invited;
  final int qualified;
  final int rewarded;
  final int capped;
  final String currency;
  final int earnedThisYearMinor;
  final int yearlyCapMinor;
  final int remainingThisYearMinor;
  final int creditSpendableMinor;
  final int creditHeldMinor;
  final int holdDays;
  final int friendDiscountPercent;

  const ReferralSummary({
    required this.code,
    required this.shareUrl,
    required this.invited,
    required this.qualified,
    required this.rewarded,
    required this.capped,
    required this.currency,
    required this.earnedThisYearMinor,
    required this.yearlyCapMinor,
    required this.remainingThisYearMinor,
    required this.creditSpendableMinor,
    required this.creditHeldMinor,
    required this.holdDays,
    required this.friendDiscountPercent,
  });

  /// True once the referrer has hit their yearly ceiling — further referrals earn
  /// nothing, and the UI says so rather than implying they still pay.
  bool get capReached => remainingThisYearMinor <= 0;

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  factory ReferralSummary.fromJson(Map<String, dynamic> j) => ReferralSummary(
        code: j['code'] as String,
        shareUrl: j['shareUrl'] as String,
        invited: _int(j['invited']),
        qualified: _int(j['qualified']),
        rewarded: _int(j['rewarded']),
        capped: _int(j['capped']),
        currency: (j['currency'] as String?) ?? 'USD',
        earnedThisYearMinor: _int(j['earnedThisYearMinor']),
        yearlyCapMinor: _int(j['yearlyCapMinor']),
        remainingThisYearMinor: _int(j['remainingThisYearMinor']),
        creditSpendableMinor: _int(j['creditSpendableMinor']),
        creditHeldMinor: _int(j['creditHeldMinor']),
        holdDays: _int(j['holdDays']),
        friendDiscountPercent: _int(j['friendDiscountPercent']),
      );
}
