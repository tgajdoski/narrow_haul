import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';

/// Boon gold and curse purple: every salvage visual is colour coded.
const Color kSalvageGood = Color(0xFFFFC857);

const Color kSalvageBad = Color(0xFFB388FF);

Color salvageColor(SalvageSpec s) => s.good ? kSalvageGood : kSalvageBad;

void drawQuestionGlyph(Canvas canvas, Offset c, double h, Color color) {
  final w = h * 0.36;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * 0.16
    ..strokeCap = StrokeCap.round;
  final top = c.dy - h * 0.5;
  final path = Path()
    ..moveTo(c.dx - w, top + w * 0.9)
    ..arcTo(Rect.fromCircle(center: Offset(c.dx, top + w), radius: w), math.pi, math.pi * 1.45, false)
    ..lineTo(c.dx, c.dy + h * 0.12);
  canvas.drawPath(path, stroke);
  canvas.drawCircle(Offset(c.dx, c.dy + h * 0.42), h * 0.09, Paint()..color = color);
}

Path _dropPath(Offset c, double s) {
  final top = Offset(c.dx, c.dy - s * 0.5);
  final r = s * 0.3;
  final ctr = Offset(c.dx, c.dy + s * 0.18);
  return Path()
    ..moveTo(top.dx, top.dy)
    ..quadraticBezierTo(c.dx + r * 1.1, c.dy - s * 0.05, ctr.dx + r, ctr.dy)
    ..arcTo(Rect.fromCircle(center: ctr, radius: r), 0, math.pi, false)
    ..quadraticBezierTo(c.dx - r * 1.1, c.dy - s * 0.05, top.dx, top.dy)
    ..close();
}

/// HUD glyph for a salvage effect ([effect] null = "?"), [s] tall.
void drawSalvageGlyph(Canvas canvas, Offset c, double s, SalvageEffect? effect, Color color) {
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.1
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..color = color;
  switch (effect) {
    case null:
      drawQuestionGlyph(canvas, c, s * 0.9, color);
    case SalvageEffect.overshield:
      canvas.drawPath(hexPath(c, s * 0.48), stroke);
      canvas.drawPath(hexPath(c, s * 0.24), fill);
    case SalvageEffect.topOff:
      canvas.drawPath(_dropPath(c.translate(-s * 0.1, 0), s * 0.85), stroke);
      final p = c.translate(s * 0.28, -s * 0.22);
      canvas.drawLine(p.translate(-s * 0.14, 0), p.translate(s * 0.14, 0), stroke);
      canvas.drawLine(p.translate(0, -s * 0.14), p.translate(0, s * 0.14), stroke);
    case SalvageEffect.afterburner:
      drawFlameGlyph(canvas, c, s * 0.95, hot: true);
    case SalvageEffect.fuelSaver:
      canvas.drawPath(_dropPath(c, s * 0.9), stroke);
      canvas.drawCircle(c.translate(0, s * 0.12), s * 0.12, stroke..strokeWidth = s * 0.07);
    case SalvageEffect.stealth:
      final eye = Path()
        ..moveTo(c.dx - s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - s * 0.42, c.dx + s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + s * 0.42, c.dx - s * 0.48, c.dy)
        ..close();
      canvas.drawPath(eye, stroke);
      canvas.drawCircle(c, s * 0.11, fill);
      canvas.drawLine(c.translate(-s * 0.42, s * 0.38), c.translate(s * 0.42, -s * 0.38), stroke);
    case SalvageEffect.swarmSting:
      drawBeeGlyph(canvas, c, s * 0.9, 0, color);
    case SalvageEffect.fuelLeak:
      canvas.drawPath(_dropPath(c.translate(0, -s * 0.06), s * 0.8), stroke);
      final crack = Path()
        ..moveTo(c.dx - s * 0.05, c.dy - s * 0.2)
        ..lineTo(c.dx + s * 0.06, c.dy - s * 0.02)
        ..lineTo(c.dx - s * 0.04, c.dy + s * 0.12);
      canvas.drawPath(crack, stroke..strokeWidth = s * 0.07);
      canvas.drawCircle(c.translate(s * 0.02, s * 0.45), s * 0.06, fill);
    case SalvageEffect.compactor:
      // Four arrows pointing in.
      for (var i = 0; i < 4; i++) {
        final d = Offset(math.cos(i * math.pi / 2 + math.pi / 4), math.sin(i * math.pi / 2 + math.pi / 4));
        final tip = c + d * s * 0.12;
        canvas.drawLine(c + d * s * 0.46, tip, stroke);
        final n = Offset(-d.dy, d.dx) * s * 0.1;
        canvas.drawLine(tip, tip + d * s * 0.13 + n, stroke);
        canvas.drawLine(tip, tip + d * s * 0.13 - n, stroke);
      }
    case SalvageEffect.chrono:
      canvas.drawCircle(c, s * 0.44, stroke);
      canvas.drawLine(c, c.translate(0, -s * 0.28), stroke);
      canvas.drawLine(c, c.translate(s * 0.2, s * 0.08), stroke);
    case SalvageEffect.antiGrav:
      canvas.drawLine(c.translate(0, s * 0.42), c.translate(0, -s * 0.4), stroke);
      canvas.drawLine(c.translate(0, -s * 0.4), c.translate(-s * 0.18, -s * 0.2), stroke);
      canvas.drawLine(c.translate(0, -s * 0.4), c.translate(s * 0.18, -s * 0.2), stroke);
      canvas.drawOval(Rect.fromCenter(center: c.translate(0, s * 0.18), width: s * 0.8, height: s * 0.24), stroke..strokeWidth = s * 0.06);
    case SalvageEffect.lucky:
      canvas.drawCircle(c, s * 0.42, fill);
      canvas.drawCircle(c, s * 0.3, Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.06);
      canvas.drawCircle(c, s * 0.1, Paint()..color = Colors.black.withValues(alpha: 0.35));
    case SalvageEffect.ammoCache:
      final box = Rect.fromCenter(center: c, width: s * 0.86, height: s * 0.6);
      canvas.drawRect(box, stroke);
      canvas.drawLine(box.centerLeft.translate(0, -s * 0.08), box.centerRight.translate(0, -s * 0.08), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * 0.12, c.dy + s * 0.2)
          ..lineTo(c.dx, c.dy + s * 0.06)
          ..lineTo(c.dx + s * 0.12, c.dy + s * 0.2),
        stroke,
      );
    case SalvageEffect.sporeTrip:
      // A mushroom: spotted cap on a stalk.
      final cap = Path()
        ..moveTo(c.dx - s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - s * 0.7, c.dx + s * 0.48, c.dy)
        ..close();
      canvas.drawPath(cap, fill);
      canvas.drawRect(Rect.fromLTRB(c.dx - s * 0.12, c.dy, c.dx + s * 0.12, c.dy + s * 0.42), stroke);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(c.translate(-s * 0.18, -s * 0.14), s * 0.07, dot);
      canvas.drawCircle(c.translate(s * 0.14, -s * 0.2), s * 0.06, dot);
    case SalvageEffect.crossedWires:
      for (final dir in [-1.0, 1.0]) {
        final y = c.dy + dir * s * 0.18;
        final from = c.dx - dir * s * 0.42, to = c.dx + dir * s * 0.42;
        canvas.drawLine(Offset(from, y), Offset(to, y), stroke);
        canvas.drawLine(Offset(to, y), Offset(to - dir * s * 0.16, y - s * 0.12), stroke);
        canvas.drawLine(Offset(to, y), Offset(to - dir * s * 0.16, y + s * 0.12), stroke);
      }
    case SalvageEffect.sputter:
      for (final (dx, dy, r) in [(-0.2, 0.1, 0.18), (0.08, -0.1, 0.22), (0.26, 0.16, 0.14)]) {
        canvas.drawCircle(c.translate(s * dx, s * dy), s * r, stroke..strokeWidth = s * 0.07);
      }
    case SalvageEffect.blackout:
      canvas.drawCircle(c, s * 0.42, fill);
      canvas.drawCircle(c.translate(s * 0.16, -s * 0.1), s * 0.36, Paint()..color = const Color(0xFF050B18));
    case SalvageEffect.hiccups:
      final z = Path()..moveTo(c.dx - s * 0.45, c.dy);
      for (var i = 1; i <= 4; i++) {
        z.lineTo(c.dx - s * 0.45 + i * s * 0.225, c.dy + (i.isOdd ? -s * 0.28 : s * 0.28));
      }
      canvas.drawPath(z, stroke);
    case SalvageEffect.heavyHeart:
      // A weight: trapezoid with a handle.
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * 0.26, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.26, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.42, c.dy + s * 0.42)
          ..lineTo(c.dx - s * 0.42, c.dy + s * 0.42)
          ..close(),
        fill,
      );
      canvas.drawCircle(c.translate(0, -s * 0.28), s * 0.14, stroke..strokeWidth = s * 0.07);
    case SalvageEffect.flareBeacon:
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * s * 0.2, c + d * s * (i.isEven ? 0.48 : 0.36), stroke);
      }
      canvas.drawCircle(c, s * 0.13, fill);
  }
}

/// A cartoon bee facing +x, [s] long; [wing] 0…1 flaps the wings.
void drawBeeGlyph(Canvas canvas, Offset c, double s, double wing, Color outline) {
  final body = Rect.fromCenter(center: c, width: s * 0.8, height: s * 0.52);
  final wingPaint = Paint()..color = const Color(0xCCE3F2FD);
  final flap = 0.6 + 0.4 * math.sin(wing * 2 * math.pi);
  canvas.drawOval(
    Rect.fromCenter(
      center: c.translate(-s * 0.05, -s * 0.3),
      width: s * 0.38,
      height: s * 0.3 * flap,
    ),
    wingPaint,
  );
  canvas.drawOval(body, Paint()..color = const Color(0xFFFFC107));
  canvas.save();
  canvas.clipPath(Path()..addOval(body));
  final stripe = Paint()..color = const Color(0xFF212121);
  for (final x in [-0.12, 0.08]) {
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(s * x, 0), width: s * 0.1, height: s),
      stripe,
    );
  }
  canvas.restore();
  // Stinger and eye.
  canvas.drawPath(
    Path()
      ..moveTo(c.dx - s * 0.38, c.dy - s * 0.06)
      ..lineTo(c.dx - s * 0.52, c.dy)
      ..lineTo(c.dx - s * 0.38, c.dy + s * 0.06)
      ..close(),
    Paint()..color = const Color(0xFF212121),
  );
  canvas.drawCircle(c.translate(s * 0.26, -s * 0.06), s * 0.05, Paint()..color = const Color(0xFF212121));
  canvas.drawOval(
    body,
    Paint()
      ..color = outline.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.04,
  );
}
