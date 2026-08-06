import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/main.dart';

void main() {
  testWidgets('App boots and renders the Seal (splash/welcome)', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WasiatiApp()));
    await tester.pump(); // one frame; bootstrap runs async
    expect(find.byType(Seal), findsWidgets);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
