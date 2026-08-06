import '../../../core/l10n/l10n.dart';

/// An estate item recorded on a will — an inventory entry, not a valuation. Heirs
/// see the item exists; the encrypted details live in the vault. "Liability" items
/// (loans / owed money) are settled before the fara'id shares are divided.
class EstateAsset {
  final String id;
  final String label;
  final String kind; // simplified UI kind: REAL_ESTATE, BANK, PENSION, VEHICLE, BUSINESS, LIABILITY, OTHER
  final String? notes;
  final double? estimatedValue;
  final String? currency; // e.g. 'SAR', 'USD', 'CAD'
  final String? institution; // held with / lender, e.g. "Al Rajhi Bank"
  final String? contactPhone; // who your heirs call
  final String? contactEmail;
  final String? accountRef; // account no / IBAN / deed no — masked in the UI

  const EstateAsset({
    required this.id,
    required this.label,
    required this.kind,
    this.notes,
    this.estimatedValue,
    this.currency,
    this.institution,
    this.contactPhone,
    this.contactEmail,
    this.accountRef,
  });

  bool get isLiability => kind == 'LIABILITY';

  /// A liability's value prefixed with a minus, e.g. "− SAR 420,000".
  String? get signedValueLabel {
    final base = valueLabel;
    if (base == null) return null;
    return isLiability ? '− $base' : base;
  }

  /// Account/IBAN/deed reference masked to its last 4 characters, prototype-style:
  /// "SA03 8000 0000 6080 1016 7519" → "SA03 ···· 7519". Null when none recorded.
  String? get maskedRef {
    final r = accountRef?.replaceAll(' ', '');
    if (r == null || r.isEmpty) return null;
    if (r.length <= 4) return r;
    final prefix = r.length > 8 ? '${r.substring(0, 4)} ' : '';
    return '$prefix···· ${r.substring(r.length - 4)}';
  }

  /// Formatted value with currency, e.g. "SAR 50,000" — or null if no value set.
  String? get valueLabel {
    final v = estimatedValue;
    if (v == null) return null;
    final n = groupedAmount(v);
    return currency == null ? n : '$currency $n';
  }

  factory EstateAsset.fromJson(Map<String, dynamic> j) {
    final rawType = (j['type'] ?? j['kind'] ?? j['category'] ?? 'OTHER').toString();
    double? val;
    final rawVal = j['estimatedValue'] ?? j['value'];
    if (rawVal != null) val = double.tryParse('$rawVal');
    return EstateAsset(
      id: j['id'] as String,
      label: (j['label'] ?? j['name'] ?? '') as String,
      kind: assetKindFromType(rawType),
      notes: (j['notes'] ?? j['description']) as String?,
      estimatedValue: val,
      currency: j['currency'] as String?,
      institution: j['institution'] as String?,
      contactPhone: j['contactPhone'] as String?,
      contactEmail: j['contactEmail'] as String?,
      accountRef: j['accountRef'] as String?,
    );
  }
}

/// Formats a number with thousands separators, e.g. 184000 → "184,000".
/// Locale-neutral (Western digits); the currency code is prepended by callers.
String groupedAmount(double v) {
  final neg = v < 0;
  final abs = v.abs();
  final whole = abs.truncate();
  final frac = abs - whole;
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  var out = buf.toString();
  if (frac > 0.0001) out += '.${abs.toStringAsFixed(2).split('.')[1]}';
  return neg ? '-$out' : out;
}

/// Maps a simplified UI kind → the backend AssetType enum value.
String assetTypeFromKind(String kind) => switch (kind) {
      'REAL_ESTATE' => 'REAL_ESTATE',
      'BANK' => 'BANK_ACCOUNT',
      'PENSION' => 'PENSION',
      'VEHICLE' => 'VEHICLE',
      'BUSINESS' => 'BUSINESS_OWNERSHIP',
      'CASH' => 'CASH',
      'SHARES' => 'SHARES',
      'GOLD' => 'GOLD',
      'CRYPTO' => 'CRYPTO',
      'LIABILITY' => 'LIABILITY',
      _ => 'OTHER',
    };

/// Maps a backend AssetType enum value (incl. region-specific accounts) → the
/// simplified UI kind used for icons, labels and the liability flag.
String assetKindFromType(String type) => switch (type) {
      'REAL_ESTATE' => 'REAL_ESTATE',
      'BANK_ACCOUNT' || 'CA_TFSA' || 'CA_RESP' || 'US_529_PLAN' => 'BANK',
      'VEHICLE' => 'VEHICLE',
      'BUSINESS_OWNERSHIP' => 'BUSINESS',
      // Zakat-relevant types. CRYPTO stays distinct so the estimator can exclude it.
      'CASH' => 'CASH',
      'SHARES' => 'SHARES',
      'GOLD' => 'GOLD',
      'CRYPTO' => 'CRYPTO',
      'PENSION' ||
      'CA_RRSP' ||
      'CA_RRIF' ||
      'US_401K' ||
      'US_IRA' ||
      'US_ROTH_IRA' ||
      'KSA_END_OF_SERVICE_BENEFITS' ||
      'KSA_GOSI_PENSION' ||
      'QA_END_OF_SERVICE_BENEFITS' ||
      'QA_GRSIA_PENSION' =>
        'PENSION',
      'LIABILITY' => 'LIABILITY',
      _ => 'OTHER',
    };

/// The currencies offered in the asset/loan entry dropdown, with the region's
/// own currency listed first.
List<String> assetCurrencies(String region) {
  final primary = switch (region) {
    'KSA' => 'SAR',
    'CA' => 'CAD',
    _ => 'USD',
  };
  final rest = ['SAR', 'QAR', 'USD', 'CAD', 'AED', 'EUR', 'GBP']..remove(primary);
  return [primary, ...rest];
}

/// A quick-add suggestion shown as a chip to ease entry (region-aware).
class AssetSuggestion {
  final String label;
  final String kind;
  const AssetSuggestion(this.label, this.kind);
}

/// Region-aware presets. Common accounts differ by region; a Liabilities set
/// (loans / owed money) is offered everywhere so debts are never forgotten.
/// Account proper nouns (RRSP, 401(k), …) stay verbatim; generic labels localise.
List<({String heading, List<AssetSuggestion> items})> assetSuggestions(AppLocalizations l, String region) {
  final regional = switch (region) {
    'KSA' => [
        AssetSuggestion(l.assetGosiPension, 'PENSION'),
        AssetSuggestion(l.assetEndOfService, 'PENSION'),
        AssetSuggestion(l.assetRealEstate, 'REAL_ESTATE'),
        AssetSuggestion(l.assetBankAccount, 'BANK'),
        AssetSuggestion(l.assetVehicle, 'VEHICLE'),
        AssetSuggestion(l.assetBusiness, 'BUSINESS'),
        AssetSuggestion(l.assetGold, 'GOLD'),
      ],
    'CA' => [
        const AssetSuggestion('RRSP', 'PENSION'),
        const AssetSuggestion('TFSA', 'BANK'),
        const AssetSuggestion('RESP', 'BANK'),
        const AssetSuggestion('RRIF', 'PENSION'),
        AssetSuggestion(l.assetRealEstate, 'REAL_ESTATE'),
        AssetSuggestion(l.assetBankAccount, 'BANK'),
        AssetSuggestion(l.assetVehicle, 'VEHICLE'),
      ],
    _ => [
        const AssetSuggestion('401(k)', 'PENSION'),
        const AssetSuggestion('IRA', 'PENSION'),
        const AssetSuggestion('Roth IRA', 'PENSION'),
        const AssetSuggestion('529 plan', 'BANK'),
        AssetSuggestion(l.assetRealEstate, 'REAL_ESTATE'),
        AssetSuggestion(l.assetBankAccount, 'BANK'),
        AssetSuggestion(l.assetVehicle, 'VEHICLE'),
      ],
  };
  return [
    (heading: l.assetSuggestedFor(_regionName(l, region)), items: regional),
    (
      heading: l.assetDebtsHeading,
      items: [
        AssetSuggestion(l.assetLoanOwed, 'LIABILITY'),
        AssetSuggestion(l.assetMortgage, 'LIABILITY'),
        AssetSuggestion(l.assetCreditCard, 'LIABILITY'),
        AssetSuggestion(l.assetUnpaidZakat, 'LIABILITY'),
      ],
    ),
  ];
}

String _regionName(AppLocalizations l, String region) => switch (region) {
      'KSA' => l.assetRegionKsa,
      'CA' => l.assetRegionCa,
      _ => l.assetRegionUs,
    };

/// The prototype's emoji icon per asset kind (🏦 Current account, 🏠 Villa,
/// 📈 Tadawul portfolio, 💼 GOSI, 🚗 Car financing…). Rendered by the browser's
/// emoji font — the golden-test harness shows boxes because it loads no emoji
/// font; real Chrome/Safari render these fine.
String assetKindEmoji(String kind) => switch (kind) {
      'REAL_ESTATE' => '🏠',
      'BANK' => '🏦',
      'CASH' => '💵',
      'SHARES' => '📈',
      'GOLD' => '🪙',
      'CRYPTO' => '🔐',
      'PENSION' => '💼',
      'VEHICLE' => '🚗',
      'BUSINESS' => '🏪',
      'LIABILITY' => '💳',
      _ => '📦',
    };

String assetKindLabel(AppLocalizations l, String kind) => switch (kind) {
      'REAL_ESTATE' => l.assetKindRealEstate,
      'BANK' => l.assetKindBank,
      'PENSION' => l.assetKindPension,
      'VEHICLE' => l.assetKindVehicle,
      'BUSINESS' => l.assetKindBusiness,
      'CASH' => l.assetKindCash,
      'SHARES' => l.assetKindShares,
      'GOLD' => l.assetKindGold,
      'CRYPTO' => l.assetKindCrypto,
      'LIABILITY' => l.assetKindLiability,
      _ => l.assetKindOther,
    };
