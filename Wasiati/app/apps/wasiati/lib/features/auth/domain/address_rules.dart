import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';

/// What a country calls its administrative area. Not display text — the label has to render
/// in Arabic too, so the choice of WORD is made here and the translation in the l10n files.
enum AreaLabel { state, province, emirate, region }

class AddressRules {
  const AddressRules({
    this.areaLabel,
    this.areaRequired = false,
    this.hasPostalCode = true,
    this.postalRequired = false,
    this.postalPattern,
  });

  final AreaLabel? areaLabel;
  final bool areaRequired;

  /// False for countries with no postal system at all — showing the field would be asking
  /// for something that does not exist.
  final bool hasPostalCode;
  final bool postalRequired;
  final RegExp? postalPattern;
}

final _rules = <String, AddressRules>{
  'US': AddressRules(
    areaLabel: AreaLabel.state,
    areaRequired: true,
    postalRequired: true,
    postalPattern: RegExp(r'^\d{5}(-\d{4})?$'),
  ),
  // Canadian postcodes exclude D, F, I, O, Q and U to avoid OCR confusion.
  'CA': AddressRules(
    areaLabel: AreaLabel.province,
    areaRequired: true,
    postalRequired: true,
    postalPattern: RegExp(r'^[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d$', caseSensitive: false),
  ),
  // Saudi postcodes exist but plenty of residents cannot recite one, so it is optional —
  // checked only when supplied.
  'SA': AddressRules(areaLabel: AreaLabel.region, areaRequired: true, postalPattern: RegExp(r'^\d{5}$')),
  // Qatar has NO postal codes and no everyday administrative area. Kept even though QA is
  // no longer a sales REGION: the market is global, and where a customer lives is a
  // different question from which price list they are on.
  'QA': const AddressRules(hasPostalCode: false),
  'AE': const AddressRules(areaLabel: AreaLabel.emirate, areaRequired: true, hasPostalCode: false),
  'GB': const AddressRules(areaLabel: AreaLabel.region, postalRequired: true),
};

/// Permissive fallback for anywhere we have no rules: line 1 + city only. A guessed rule that
/// rejects someone's real address is worse than no rule.
const _fallback = AddressRules();

AddressRules addressRulesFor(String country) => _rules[country.toUpperCase()] ?? _fallback;

String areaLabelText(BuildContext context, AreaLabel label) {
  final l = context.l10n;
  return switch (label) {
    AreaLabel.state => l.addrState,
    AreaLabel.province => l.addrProvince,
    AreaLabel.emirate => l.addrEmirate,
    AreaLabel.region => l.addrRegion,
  };
}

