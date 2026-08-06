// Sign-up offers every country, not the six we happen to know postcode rules for.
//
// The picker listed US, CA, SA, QA, AE and GB. That list lived next to the address-FORMAT
// rules in address_rules.dart, and those rules are only known for a handful of places — so
// the two got conflated and the picker inherited the short list.
//
// They are different questions. The backend has always accepted any ISO country
// (@IsISO31661Alpha2 on RegisterDto) and has always had a permissive address format for
// countries whose conventions it does not know (address-format.ts). The client was
// narrower than the server for no reason, and Wasiati sells globally: the four countries
// with the largest Muslim populations on earth — Indonesia, Pakistan, India, Bangladesh —
// were all missing, so those customers could not enter where they live.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/auth/presentation/address_fields.dart';
import 'package:wasiati/features/auth/domain/address_rules.dart';
import 'package:wasiati/features/auth/domain/countries.dart';

void main() {
  group('the country list', () {
    test('covers the whole ISO 3166-1 alpha-2 set, not a market shortlist', () {
      // ~250 assigned codes; ICU also carries a few territories with their own postal
      // systems (Hong Kong, Puerto Rico, Guernsey), which belong in an address picker.
      expect(kCountries.length, greaterThan(240));
    });

    test('includes the largest Muslim populations, none of which were listed before', () {
      // Indonesia, Pakistan, India, Bangladesh, Nigeria, Egypt, Turkey, Iran, Malaysia —
      // and none of them were in the six.
      for (final code in const ['ID', 'PK', 'IN', 'BD', 'NG', 'EG', 'TR', 'IR', 'MY']) {
        expect(countryFor(code), isNotNull, reason: '$code must be selectable at sign-up');
      }
    });

    test('still includes the original six', () {
      for (final code in const ['US', 'CA', 'SA', 'QA', 'AE', 'GB']) {
        expect(countryFor(code), isNotNull);
      }
    });

    test('every entry carries a real name in both languages, never a bare code', () {
      for (final c in kCountries) {
        expect(c.en, isNotEmpty);
        expect(c.ar, isNotEmpty);
        expect(c.en, isNot(c.code), reason: '${c.code} has no English name — ICU gap');
        // Arabic names come from ICU too; a code here means the generator fell through.
        expect(c.ar, isNot(c.code), reason: '${c.code} has no Arabic name — ICU gap');
      }
    });

    test('codes are unique and well-formed', () {
      final seen = <String>{};
      for (final c in kCountries) {
        expect(c.code, matches(RegExp(r'^[A-Z]{2}$')));
        expect(seen.add(c.code), isTrue, reason: '${c.code} listed twice');
      }
    });

    test('excludes the supranational aggregates ICU also answers for', () {
      // "European Union" and "Outlying Oceania" are not places anyone lives.
      for (final code in const ['EU', 'UN', 'QO', 'ZZ']) {
        expect(countryFor(code), isNull, reason: '$code is not a country');
      }
    });
  });

  group('display order', () {
    test('sorts by the localized name, not by code', () {
      final en = countriesSortedFor('en');
      expect(en.first.en.compareTo(en.last.en), lessThan(0));
      // Code order would put AD first; name order puts Afghanistan first in English.
      expect(en.first.code, isNot('AD'));

      final ar = countriesSortedFor('ar');
      expect(ar.first.ar.compareTo(ar.last.ar), lessThan(0));
      // The two locales genuinely order differently — alphabetical-by-English would be
      // meaningless to an Arabic reader.
      expect(ar.first.code, isNot(en.first.code));
    });

    test('nameFor picks the locale, falling back to English', () {
      final eg = countryFor('EG')!;
      expect(eg.nameFor('ar'), isNot(eg.nameFor('en')));
      expect(eg.nameFor('fr'), eg.en, reason: 'only en and ar ship; anything else reads English');
    });
  });

  group('address rules stay a separate, short list', () {
    test('the six known formats still apply', () {
      // Widening the picker must not have widened the FORMAT rules — those are only
      // correct where someone checked them.
      expect(addressRulesFor('US').postalRequired, isTrue);
      expect(addressRulesFor('CA').postalRequired, isTrue);
      expect(addressRulesFor('QA').hasPostalCode, isFalse,
          reason: 'Qatar has no postcodes; requiring one locks the address out');
    });

    test('an unknown country gets the permissive default, not a rejection', () {
      // The whole reason the picker can be global: a country we know nothing about still
      // has a usable form. Line 1 + city, nothing forced that may not exist.
      for (final code in const ['ID', 'NG', 'JP', 'BR']) {
        final rules = addressRulesFor(code);
        expect(rules.postalRequired, isFalse, reason: '$code must not force a postcode we cannot validate');
        expect(rules.areaRequired, isFalse, reason: '$code must not force an area that may not exist');
      }
    });
  });

  _pickerTests();
}

/// The picker end to end: a country that was never in the old six can be found by typing
/// and selected, and the choice reaches the form.
void _pickerTests() {
  testWidgets('typing filters the list and selecting reports the ISO code', (t) async {
    t.view.physicalSize = const Size(520, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    String? picked;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: AddressFields(
            country: 'US',
            onCountryChanged: (c) => picked = c,
            line1: TextEditingController(),
            line2: TextEditingController(),
            city: TextEditingController(),
            area: TextEditingController(),
            postal: TextEditingController(),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    // The field shows the current selection by NAME, not by code. Read off the text
    // field's own controller: DropdownMenu builds every entry into the tree, so a bare
    // find.text('United States') also matches the hidden menu row.
    String fieldText() => t.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(fieldText(), 'United States');

    await t.tap(find.byType(TextField).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Malays');
    await t.pumpAndSettle();

    // Malaysia was not one of the six. Scrolling 267 entries is not a form, so the filter
    // is the feature: it has to actually narrow. Scoped to the open menu so the field's
    // own text is not what satisfies the assertion.
    final menu = find.byType(SingleChildScrollView);
    expect(find.descendant(of: menu, matching: find.text('Malaysia')), findsOneWidget);
    expect(find.descendant(of: menu, matching: find.text('United States')), findsNothing,
        reason: 'the filter must exclude non-matches');

    await t.tap(find.descendant(of: menu, matching: find.text('Malaysia')));
    await t.pumpAndSettle();
    expect(picked, 'MY', reason: 'the form receives the ISO code, not the display name');
  });
}
