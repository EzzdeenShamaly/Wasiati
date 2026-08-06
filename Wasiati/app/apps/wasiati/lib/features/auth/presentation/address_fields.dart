import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/address_rules.dart';
import '../domain/countries.dart';

/// The postal-address block on signup, laid out per country.
///
/// Three things change between countries and all three are visible to the user: which fields
/// are REQUIRED, what the administrative area is CALLED, and whether a postal code exists at
/// all. Showing one fixed form everywhere either rejects valid addresses — Qatar has no
/// postal codes, so a required postcode locks out the market — or accepts unusable ones,
/// which then get printed into a legal document.
///
/// The rules mirror the server's (backend/src/common/address-format.ts); the server is
/// authoritative and returns the offending field names, this just avoids a round trip to
/// learn something the form could have said immediately.
class AddressFields extends StatelessWidget {
  const AddressFields({
    super.key,
    required this.country,
    required this.onCountryChanged,
    required this.line1,
    required this.line2,
    required this.city,
    required this.area,
    required this.postal,
  });

  final String country;
  final ValueChanged<String> onCountryChanged;
  final TextEditingController line1;
  final TextEditingController line2;
  final TextEditingController city;
  final TextEditingController area;
  final TextEditingController postal;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rules = addressRulesFor(country);

    String? required$(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CountryPicker(value: country, onChanged: onCountryChanged),
      const SizedBox(height: 14),
      TextFormField(
        controller: line1,
        autofillHints: const [AutofillHints.streetAddressLine1],
        decoration: InputDecoration(labelText: l.addrLine1),
        validator: (v) => required$(v, l.addrLine1Required),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: line2,
        autofillHints: const [AutofillHints.streetAddressLine2],
        decoration: InputDecoration(labelText: l.addrLine2Optional),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: city,
        autofillHints: const [AutofillHints.addressCity],
        decoration: InputDecoration(labelText: l.addrCity),
        validator: (v) => required$(v, l.addrCityRequired),
      ),
      if (rules.areaLabel != null) ...[
        const SizedBox(height: 14),
        TextFormField(
          controller: area,
          autofillHints: const [AutofillHints.addressState],
          // "State", "Province", "Emirate", "Region" — the same field, named the way the
          // country names it. A Canadian asked for their "state" reads as a form written
          // for somewhere else.
          decoration: InputDecoration(labelText: areaLabelText(context, rules.areaLabel!)),
          validator: rules.areaRequired ? (v) => required$(v, l.addrAreaRequired) : null,
        ),
      ],
      if (rules.hasPostalCode) ...[
        const SizedBox(height: 14),
        TextFormField(
          controller: postal,
          autofillHints: const [AutofillHints.postalCode],
          decoration: InputDecoration(
            labelText: rules.postalRequired ? l.addrPostalCode : l.addrPostalCodeOptional,
          ),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return rules.postalRequired ? l.addrPostalRequired : null;
            // An optional-but-wrong postcode is still wrong.
            if (rules.postalPattern != null && !rules.postalPattern!.hasMatch(s)) {
              return l.addrPostalInvalid;
            }
            return null;
          },
        ),
      ],
    ]);
  }
}

/// Country picker over the full ISO 3166-1 list, with type-to-filter.
///
/// This was a plain DropdownButtonFormField over six hand-listed countries — US, CA, SA,
/// QA, AE, GB — because the list lived beside the address-FORMAT rules, and those are only
/// known for a handful of places. But they are different questions. The backend has always
/// accepted any ISO country (@IsISO31661Alpha2 on RegisterDto) and has always had a
/// permissive format for countries whose conventions it does not know. The client was
/// narrower than the server for no reason, and Wasiati sells globally: someone in Malaysia,
/// Indonesia, Pakistan or Nigeria simply could not say where they live.
///
/// 267 entries need search — scrolling that list to find "Singapore" is not a form, it is a
/// punishment — so this is a DropdownMenu with enableFilter rather than a Dropdown.
class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  final _controller = TextEditingController();
  String? _lastSyncedTo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final countries = countriesSortedFor(lang);

    // Keep the field's text in step with the selected code — including the initial value,
    // which is set from the deployment region before this widget is ever touched, and a
    // locale switch, which renames every country under it.
    final syncKey = '${widget.value}/$lang';
    if (_lastSyncedTo != syncKey) {
      _lastSyncedTo = syncKey;
      _controller.text = countryFor(widget.value)?.nameFor(lang) ?? widget.value;
    }

    return LayoutBuilder(builder: (context, box) {
      return DropdownMenu<String>(
        controller: _controller,
        initialSelection: widget.value,
        label: Text(l.addrCountry),
        // Matches the width of the text fields below it; DropdownMenu does not stretch on
        // its own and a half-width country field beside full-width address lines looks
        // like a mistake.
        width: box.maxWidth,
        menuHeight: 360,
        enableFilter: true,
        requestFocusOnTap: true,
        onSelected: (v) {
          if (v != null) widget.onChanged(v);
        },
        dropdownMenuEntries: [
          for (final c in countries) DropdownMenuEntry<String>(value: c.code, label: c.nameFor(lang)),
        ],
      );
    });
  }
}
