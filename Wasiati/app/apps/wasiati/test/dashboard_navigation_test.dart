import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';

/// The dashboard's estate tiles and checklist rows each stand for one section of the
/// will. Two ways that went wrong, both reported by the owner:
///
///   * "witnesses goes nowhere from dashboard" — the tile had no onTap at all, and
///     nor did the trustee tile;
///   * "heir contacts takes me to the wrong page" — the tile navigated to the top of
///     the will detail page, leaving the owner to hunt for the section they tapped.
///
/// The fix is `?focus=`, parsed here. These pin the contract between the two screens:
/// the dashboard builds the query, the router parses it, the detail screen scrolls.
/// A typo on either side silently restores the old behaviour, because an unknown
/// value simply means "don't scroll".
void main() {
  group('willSectionFrom', () {
    test('parses the three section names the dashboard emits', () {
      expect(willSectionFrom('heirs'), WillSection.heirs);
      expect(willSectionFrom('witnesses'), WillSection.witnesses);
      expect(willSectionFrom('trustees'), WillSection.trustees);
    });

    test('is null for an absent or unknown focus, so the page just opens at the top', () {
      expect(willSectionFrom(null), isNull);
      expect(willSectionFrom(''), isNull);
      expect(willSectionFrom('bequests'), isNull);
      // Case matters: the dashboard emits lowercase, and quietly accepting other
      // spellings would hide a mismatch rather than surface it.
      expect(willSectionFrom('Heirs'), isNull);
    });

    test('covers every section — a new enum value must be given a name here', () {
      for (final s in WillSection.values) {
        expect(willSectionFrom(s.name), s,
            reason: 'WillSection.${s.name} has no parse case, so ?focus=${s.name} would be ignored.');
      }
    });
  });
}
