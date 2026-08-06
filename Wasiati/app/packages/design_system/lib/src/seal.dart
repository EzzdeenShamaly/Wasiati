import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'colors.dart';

/// The signed-W brand seal: the Rub-el-Hizb (two overlapping rounded squares) in
/// bottle green, the one-stroke parchment W, and the gold ink drop floating above
/// its peak. Exact vector paths from the design canvas (Brand & Logo). Distinct
/// from [Seal], which is the status indicator.
class WasiatiSeal extends StatelessWidget {
  final double size;
  const WasiatiSeal({super.key, this.size = 72});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _BrandSealPainter());
}

class _BrandSealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 100);
    final green = Paint()..color = WasiatiColors.bottleGreen;
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-27, -27, 54, 54), const Radius.circular(8));
    canvas.drawRRect(body, green);
    canvas.save();
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(body, green);
    canvas.restore();
    // One-stroke W.
    final w = Path()
      ..moveTo(-16, -6)
      ..cubicTo(-13, 4, -10, 11, -8, 11)
      ..cubicTo(-5.5, 11, -3.5, 3, 0, -5)
      ..cubicTo(3.5, 3, 5.5, 11, 8, 11)
      ..cubicTo(10.5, 11, 13, 4, 16, -6);
    canvas.drawPath(
      w,
      Paint()
        ..color = WasiatiColors.parchment
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(const Offset(0, -10.5), 4.1, green); // notch
    // Gold ink drop above the peak (SVG transform chain, verbatim).
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
    canvas.drawPath(drop, Paint()..color = WasiatiColors.brassGold);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The eight-point geometric seal (Rub-el-Hizb) — Wasiati's signature mark and
/// the literal status indicator used across the product: a will/vault item is
/// idle, then locked, sealed, witnessed, verified — or rejected (KYC).
///
/// Per the design handoff: idle is an OUTLINE (#B0A48C) with a centre dot; every
/// other state is a SOLID seal filled with the state colour and a parchment glyph.
enum SealStatus { idle, locked, sealed, witnessed, verified, rejected }

class Seal extends StatelessWidget {
  final double size;
  final SealStatus status;

  /// Retained for source compatibility; fill is now driven by [status].
  final bool filled;

  const Seal({super.key, this.size = 48, this.status = SealStatus.idle, this.filled = false});

  static const _idle = Color(0xFFB0A48C);

  Color get color => switch (status) {
        SealStatus.idle => _idle,
        SealStatus.locked => WasiatiColors.bottleGreen,
        SealStatus.sealed => WasiatiColors.brassGold,
        SealStatus.witnessed => WasiatiColors.info,
        SealStatus.verified => WasiatiColors.success,
        SealStatus.rejected => WasiatiColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SealPainter(color: color, status: status)),
    );
  }
}

class _SealPainter extends CustomPainter {
  final Color color;
  final SealStatus status;
  _SealPainter({required this.color, required this.status});

  static const _glyphColor = WasiatiColors.onDark; // parchment glyph on filled seals

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * 0.94;
    final stroke = size.width * 0.096; // ~5px at 52 (idle outline weight)

    Path square(double rot) {
      final p = Path();
      for (var i = 0; i < 4; i++) {
        final a = rot + i * math.pi / 2;
        final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    }

    // Two overlapping squares (one rotated 45°) => the 8-point star seal.
    final star = Path.combine(PathOperation.union, square(-math.pi / 2), square(-math.pi / 2 + math.pi / 4));

    if (status == SealStatus.idle) {
      canvas.drawPath(
        star,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(c, stroke * 0.85, Paint()..color = color);
      return;
    }

    // Solid seal + subtle inner hairline ring, glyph in parchment.
    canvas.drawPath(star, Paint()..color = color);
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..color = _glyphColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.35,
    );
    _glyph(canvas, c, r * 0.34, stroke);
  }

  void _glyph(Canvas canvas, Offset c, double r, double stroke) {
    final paint = Paint()
      ..color = _glyphColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (status) {
      case SealStatus.verified:
      case SealStatus.witnessed:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.5, c.dy)
            ..lineTo(c.dx - r * 0.08, c.dy + r * 0.45)
            ..lineTo(c.dx + r * 0.6, c.dy - r * 0.5),
          paint,
        );
      case SealStatus.rejected:
        canvas.drawLine(Offset(c.dx - r * 0.45, c.dy - r * 0.45), Offset(c.dx + r * 0.45, c.dy + r * 0.45), paint);
        canvas.drawLine(Offset(c.dx + r * 0.45, c.dy - r * 0.45), Offset(c.dx - r * 0.45, c.dy + r * 0.45), paint);
      case SealStatus.locked:
      case SealStatus.sealed:
        final body = Rect.fromLTWH(c.dx - r * 0.5, c.dy - r * 0.05, r, r * 0.72);
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(r * 0.14)),
          paint..style = PaintingStyle.stroke,
        );
        canvas.drawArc(Rect.fromLTWH(c.dx - r * 0.3, c.dy - r * 0.55, r * 0.6, r * 0.62), math.pi, math.pi, false, paint);
      case SealStatus.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SealPainter old) => old.color != color || old.status != status;
}
