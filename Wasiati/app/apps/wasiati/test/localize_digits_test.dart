import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/l10n/l10n.dart';

/// The app's Arabic copy is Arabic-Indic (WASIATI_HANDOFF: "Arabic numerals (٠١٢…) in AR
/// locale"), but every number the app COMPUTES arrives Western — so it must be mapped at
/// display or it reads in the wrong system beside the static copy. This pins that map.
void main() {
  group('localizeDigits', () {
    test('is identity for non-Arabic locales', () {
      expect(localizeDigits('Step 3 of 6', 'en'), 'Step 3 of 6');
      expect(localizeDigits('1,234.5', 'fr'), '1,234.5');
    });

    test('maps ASCII digits to Arabic-Indic under ar', () {
      expect(localizeDigits('0123456789', 'ar'), '٠١٢٣٤٥٦٧٨٩');
      // The exact sentence that was mixing systems: injected Western beside literal ٦.
      expect(localizeDigits('الخطوة 3 من ٦', 'ar'), 'الخطوة ٣ من ٦');
    });

    test('touches only digits — letters, currency codes and separators survive', () {
      expect(localizeDigits('1,234 SAR', 'ar'), '١,٢٣٤ SAR');
      expect(localizeDigits('12.5%', 'ar'), '١٢.٥%');
    });

    test('is idempotent — already-Arabic-Indic digits pass through', () {
      const already = '٠٢:١٤';
      expect(localizeDigits(already, 'ar'), already);
    });
  });
}
