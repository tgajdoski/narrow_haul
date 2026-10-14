import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'shapes.dart';


class HoloFramePainter extends CustomPainter {
  HoloFramePainter({
    required this.accent,
    required this.fill,
    required this.cut,
    required this.glow,
    required this.brackets,
    required this.scanlines,
    this.borderAlpha = 0.75,
    this.fillGradient = true,
  });

  final Color accent;
  final Color fill;
  final double cut;
  final double glow;
  final bool brackets;
  final bool scanlines;
  final double borderAlpha;
  final bool fillGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final path = chamferPath(r.deflate(0.75), cut);

    if (glow > 0) {
      canvas.drawPath(
        path,
        GlowPaint.of(accent.withValues(alpha: 0.35 * glow), 6, 8 * glow),
      );
    }

    final fillPaint = Paint()..color = fill;
    if (fillGradient) {
      fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(accent.withValues(alpha: 0.10), fill), fill],
      ).createShader(r);
    }
    canvas.drawPath(path, fillPaint);

    if (scanlines) {
      canvas.save();
      canvas.clipPath(path);
      final line = Paint()..color = Colors.white.withValues(alpha: 0.025);
      for (var y = 1.0; y < size.height; y += 3) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
      canvas.restore();
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: borderAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    if (brackets) {
      // Bright corner ticks on the two big chamfers.
      final c = math.min(cut, math.min(size.width, size.height) / 2);
      final p = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.square;
      final arm = math.min(18.0, size.width / 6);
      canvas.drawLine(Offset(1, c + 1), Offset(c + 1, 1), p);
      canvas.drawLine(Offset(c + 1, 1), Offset(c + 1 + arm, 1), p);
      canvas.drawLine(
        Offset(size.width - 1, size.height - c - 1),
        Offset(size.width - c - 1, size.height - 1),
        p,
      );
      canvas.drawLine(
        Offset(size.width - c - 1, size.height - 1),
        Offset(size.width - c - 1 - arm, size.height - 1),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(HoloFramePainter o) =>
      o.accent != accent ||
      o.fill != fill ||
      o.cut != cut ||
      o.glow != glow ||
      o.brackets != brackets ||
      o.scanlines != scanlines ||
      o.borderAlpha != borderAlpha;
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels
// ─────────────────────────────────────────────────────────────────────────────
