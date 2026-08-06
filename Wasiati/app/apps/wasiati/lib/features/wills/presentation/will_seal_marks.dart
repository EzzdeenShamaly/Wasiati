import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The two seals the DV2.1 will document carries: a gold lock-seal at the head of
/// the sheet and a larger gold check-rosette in the sealed footer. Both are the
/// prototype's inline SVGs (Will export screen, lines 1713 and 1804) drawn as
/// native paths so they stay crisp at any size instead of rasterising with the PDF.
///
/// The two brand colours are LITERAL, not theme tokens: the seal is gold-on-cream
/// by design and reads identically in light and dark, exactly as the SVG does — a
/// theme-swapped seal would turn the cream padlock murky on a night sheet.
const Color _gold = Color(0xFFA87B33); // brassGold
const Color _cream = Color(0xFFF5EFE1); // parchmentLight

/// The two overlapping rounded squares (one rotated 45°) shared by both marks —
/// the Rub-el-Hizb footprint the seal glyph is built on. Drawn in the SVG's
/// 100×100 space; the caller has already scaled and centred the canvas.
void _paintRosetteBody(Canvas canvas) {
  final square = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-26, -26, 52, 52),
    const Radius.circular(7),
  );
  final gold = Paint()..color = _gold;
  canvas.drawRRect(square, gold);
  canvas.save();
  canvas.rotate(math.pi / 4);
  canvas.drawRRect(square, gold);
  canvas.restore();
}

/// Gold lock-seal — the header mark. A cream padlock (shackle + body) over the
/// gold rosette. Default 52px to match the prototype's header seal.
class WillLockSeal extends StatelessWidget {
  const WillLockSeal({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _LockSealPainter());
}

class _LockSealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 100);
    _paintRosetteBody(canvas);

    // Padlock shackle: SVG "M-7 -4 v-5 a7 7 0 0 1 14 0 v5" — up, a clockwise
    // semicircle over the top, back down. Stroke only, no fill.
    final shackle = Path()
      ..moveTo(-7, -4)
      ..lineTo(-7, -9)
      ..arcToPoint(const Offset(7, -9), radius: const Radius.circular(7), clockwise: true)
      ..lineTo(7, -4);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = _cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    // Padlock body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -4, 22, 17), const Radius.circular(4)),
      Paint()..color = _cream,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Gold check-rosette — the sealed-footer mark. A cream check over the gold
/// rosette. Default 120px to match the prototype's footer seal.
class WillSealRosette extends StatelessWidget {
  const WillSealRosette({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _RosettePainter());
}

class _RosettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 100);
    _paintRosetteBody(canvas);

    // Check mark: SVG "M-11 1 L-3 9 L12 -9", round caps and joins.
    final check = Path()
      ..moveTo(-11, 1)
      ..lineTo(-3, 9)
      ..lineTo(12, -9);
    canvas.drawPath(
      check,
      Paint()
        ..color = _cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
