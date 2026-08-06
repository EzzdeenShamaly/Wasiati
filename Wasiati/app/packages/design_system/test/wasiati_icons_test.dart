import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

void main() {
  // Every catalogue glyph, so the loop below renders each one.
  const icons = <String, String>{
    'home': WasiatiIcons.home,
    'wills': WasiatiIcons.wills,
    'vault': WasiatiIcons.vault,
    'burial': WasiatiIcons.burial,
    'guided': WasiatiIcons.guided,
    'identity': WasiatiIcons.identity,
    'plans': WasiatiIcons.plans,
    'settings': WasiatiIcons.settings,
    'admin': WasiatiIcons.admin,
    'users': WasiatiIcons.users,
    'claims': WasiatiIcons.claims,
    'heirContacts': WasiatiIcons.heirContacts,
    'witnesses': WasiatiIcons.witnesses,
    'trustee': WasiatiIcons.trustee,
    'chevronRight': WasiatiIcons.chevronRight,
    'back': WasiatiIcons.back,
    'add': WasiatiIcons.add,
    'edit': WasiatiIcons.edit,
    'download': WasiatiIcons.download,
    'check': WasiatiIcons.check,
    'mic': WasiatiIcons.mic,
    'signOut': WasiatiIcons.signOut,
  };

  testWidgets('every WasiatiIcon renders without throwing', (tester) async {
    for (final entry in icons.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: WasiatiIcon(svg: entry.value, size: 24, color: const Color(0xFF1C2333)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WasiatiIcon), findsOneWidget, reason: 'icon "${entry.key}" failed to build');
      expect(tester.takeException(), isNull, reason: 'icon "${entry.key}" threw while rendering');
    }
  });

  testWidgets('color null falls back to inherited text colour', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTextStyle(
          style: TextStyle(color: Color(0xFFC9A45E)),
          child: Center(child: WasiatiIcon(svg: WasiatiIcons.home, size: 22)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
