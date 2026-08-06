import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

// Renders the brand logo + status seals large to inspect orientation. Run:
//   flutter test --update-goldens test/_capture_logo.dart
Future<void> _fonts() async {
  final l = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await l.load();
}

void main() {
  testWidgets('logos', (t) async {
    await _fonts();
    t.view.physicalSize = const Size(900, 320);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFFECE3D0),
        body: Center(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('landing logo (_LogoSeal)'),
              SizedBox(height: 8),
              SizedBox(width: 180, height: 180, child: CustomPaint(painter: _LogoPainter())),
            ]),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Seal(sealed)'),
              SizedBox(height: 8),
              Seal(size: 180, status: SealStatus.sealed),
            ]),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await expectLater(find.byType(Row), matchesGoldenFile('cap_logo.png'));
  });
}

// Copy of welcome_screen's _LogoPainter to inspect it in isolation.
class _LogoPainter extends CustomPainter {
  const _LogoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    final seal = Paint()..color = const Color(0xFF2F4A3D);
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-27, -27, 54, 54), const Radius.circular(8));
    canvas.drawRRect(body, seal);
    canvas.save();
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(body, seal);
    canvas.restore();
    final w = Path()
      ..moveTo(-16, -6)
      ..cubicTo(-13, 4, -10, 11, -8, 11)
      ..cubicTo(-5.5, 11, -3.5, 3, 0, -5)
      ..cubicTo(3.5, 3, 5.5, 11, 8, 11)
      ..cubicTo(10.5, 11, 13, 4, 16, -6);
    canvas.drawPath(
        w,
        Paint()
          ..color = const Color(0xFFECE3D0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(const Offset(0, -10.5), 4.1, seal);
    canvas.save();
    canvas.translate(0, 2.2);
    canvas.translate(0, -15.5);
    canvas.scale(0.85, -0.85);
    canvas.translate(0, 15.5);
    final drop = Path()
      ..moveTo(0, -10)
      ..cubicTo(-0.8, -12.5, -4, -15, -4, -16.8)
      ..cubicTo(-4, -19.4, -2.2, -21, 0, -21)
      ..cubicTo(2.2, -21, 4, -19.4, 4, -16.8)
      ..cubicTo(4, -15, 2.8, -12.5, 0, -10)
      ..close();
    canvas.drawPath(drop, Paint()..color = const Color(0xFFA87B33));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
