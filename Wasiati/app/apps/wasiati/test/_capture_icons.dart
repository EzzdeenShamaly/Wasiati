import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

// Renders every WasiatiIcons glyph in a labelled grid so we can eyeball them.
//   flutter test --update-goldens test/_capture_icons.dart
Future<void> _load(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final a in assets) {
    loader.addFont(rootBundle.load(a));
  }
  await loader.load();
}

void main() {
  testWidgets('icons', (t) async {
    await _load('Public Sans', ['assets/fonts/PublicSans.ttf']);
    const entries = <String, String>{
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
    t.view.physicalSize = const Size(900, 700);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFECE3D0),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Wrap(
            spacing: 20,
            runSpacing: 22,
            children: [
              for (final e in entries.entries)
                SizedBox(
                  width: 120,
                  child: Column(children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF5EFE1), borderRadius: BorderRadius.circular(14)),
                      child: Center(child: WasiatiIcon(svg: e.value, size: 28, color: const Color(0xFF2F4A3D))),
                    ),
                    const SizedBox(height: 6),
                    Text(e.key, style: const TextStyle(fontFamily: 'Public Sans', fontSize: 11, color: Color(0xFF1C2333))),
                  ]),
                ),
            ],
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('cap_icons.png'));
  });
}
