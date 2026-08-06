// Every signature on the will document must carry the date THAT PERSON acted.
//
// The sheet used to stamp `will.sealedAt` on all of them — witnesses, trustee and
// testator alike — dating each signature with the one day nobody signed anything.
// The server has always sent the real dates (findOne returns full witness/trustee
// rows; its own PDF renderer uses witness.signedAt / trustee.confirmedAt /
// will.signedAt ?? sealedAt), and the client models dropped them. The person relying
// on these dates is a probate clerk comparing this sheet against the server's PDF:
// the two documents disagreed about when every signature happened.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_document_sheet.dart';

void main() {
  // The realistic sequence: the owner signs, the witnesses sign on their own days,
  // the trustee confirms, and only then does the will seal.
  final will = Will(
    id: 'w1234567',
    tier: 'STANDARD',
    locked: true,
    status: 'SEALED',
    signedAt: DateTime.utc(2026, 3, 1),
    sealedAt: DateTime.utc(2026, 3, 10),
    shariaShares: const [ShariaShare(heirRelation: 'SON', heirName: 'Tariq', sharePercent: 100)],
  );
  final witnesses = [
    Witness(id: 'a', fullName: 'Khalid', phone: '+1555', status: 'SIGNED', signedAt: DateTime.utc(2026, 3, 3)),
    Witness(id: 'b', fullName: 'Omar', phone: '+1556', status: 'SIGNED', signedAt: DateTime.utc(2026, 3, 7)),
  ];
  final trustees = [
    Trustee(id: 't', fullName: 'Fatima', phone: '+1557', status: 'CONFIRMED', confirmedAt: DateTime.utc(2026, 3, 5)),
  ];

  Future<void> pump(WidgetTester t, {List<Witness>? wit, List<Trustee>? tru, Will? w}) async {
    await t.binding.setSurfaceSize(const Size(900, 2400));
    await t.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SingleChildScrollView(
        child: WillDocumentSheet(
          will: w ?? will,
          assets: const [],
          witnesses: wit ?? witnesses,
          trustees: tru ?? trustees,
          testatorName: 'ahmed',
          city: 'Toronto',
          country: 'CA',
          format: 'classic',
          display: 'percent',
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('each signature carries its OWN date, none the seal date', (t) async {
    await pump(t);

    expect(find.textContaining('3 March 2026'), findsOneWidget); // Khalid signed
    expect(find.textContaining('7 March 2026'), findsOneWidget); // Omar signed
    expect(find.textContaining('5 March 2026'), findsOneWidget); // Fatima confirmed
    expect(find.textContaining('1 March 2026'), findsOneWidget); // the testator signed

    // The seal date belongs to the header/footer ("Sealed & witnessed…"), never to a
    // signature row: exactly one Signed-digitally line may not carry 10 Mar.
    final sigLines = t
        .widgetList<Text>(find.textContaining('Signed digitally'))
        .map((w) => w.data ?? '')
        .toList();
    expect(sigLines, hasLength(4));
    expect(sigLines.where((s) => s.contains('10 March 2026')), isEmpty);
  });

  testWidgets('a sealed will from before signedAt was recorded still shows dates — the seal fallback', (t) async {
    // Old rows carry no per-signature dates. Undated is honest for witnesses; the
    // testator falls back to sealedAt, the server renderer's exact rule.
    await pump(
      t,
      w: Will(
        id: 'w1234567',
        tier: 'STANDARD',
        locked: true,
        status: 'SEALED',
        sealedAt: DateTime.utc(2026, 3, 10),
        shariaShares: const [ShariaShare(heirRelation: 'SON', heirName: 'Tariq', sharePercent: 100)],
      ),
      wit: [const Witness(id: 'a', fullName: 'Khalid', phone: '+1555', status: 'SIGNED')],
      tru: [const Trustee(id: 't', fullName: 'Fatima', phone: '+1557', status: 'CONFIRMED')],
    );

    final sigLines = t
        .widgetList<Text>(find.textContaining('Signed digitally'))
        .map((w) => w.data ?? '')
        .toList();
    expect(sigLines, hasLength(3));
    // Only the testator's line carries the fallback date.
    expect(sigLines.where((s) => s.contains('10 March 2026')), hasLength(1));
  });

  testWidgets('an unsealed WITNESSED will already shows who signed when', (t) async {
    // Before the fix a signed witness on an unsealed will showed NO date at all —
    // the date was gated on _sealed because it had nothing per-person to show.
    await pump(
      t,
      w: Will(
        id: 'w1234567',
        tier: 'STANDARD',
        locked: true,
        status: 'WITNESSED',
        signedAt: DateTime.utc(2026, 3, 1),
        shariaShares: const [ShariaShare(heirRelation: 'SON', heirName: 'Tariq', sharePercent: 100)],
      ),
    );

    expect(find.textContaining('3 March 2026'), findsOneWidget);
    expect(find.textContaining('5 March 2026'), findsOneWidget);
  });
}
