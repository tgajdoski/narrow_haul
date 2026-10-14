import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// A horizontal fuel gauge drawn directly to viewport canvas.
class FuelGaugeHud extends PositionComponent {
  FuelGaugeHud() : super(priority: 4900);

  double fuelFraction = 1.0;
  bool towing = false;

  /// Fuel fractions needed for 3★ / 2★ — drawn as ticks on the bar.
  List<double> starMarks = const [];

  static const double lowFuel = 0.15;
  double _t = 0;

  /// Fuel just spent on shots (share of the tank), shown at the fill edge
  /// for a moment: the cost lands where the pilot reads the tank.
  double _costFrac = 0;
  double _costLeft = 0;
  static const double _costSeconds = 0.9;

  /// A shot (or burst) cost [frac] of the tank; quick shots add up.
  void flashCost(double frac) {
    _costFrac = (_costLeft > 0 ? _costFrac : 0) + frac;
    _costLeft = _costSeconds;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_costLeft > 0) _costLeft = math.max(0, _costLeft - dt);
  }

  final _fuelLabel = HudText();
  final _lowLabel = HudText();
  final _costLabel = HudText();

  static const double _barW = 220.0;
  static const double _barH = 26.0;
  static const double _left = 12.0;
  static const double _top = 8.0;
  static const int _segments = 24;

  @override
  void render(Canvas canvas) {
    final fillColor = fuelFraction > 0.4
        ? HudColors.cyan
        : fuelFraction > 0.15
            ? const Color(0xFFFFD166)
            : HudColors.warn;
    // Low fuel: the fill blinks so it's noticed in peripheral vision.
    final low = fuelFraction > 0 && fuelFraction < lowFuel;
    final blink = low ? 0.35 + 0.65 * (math.sin(_t * 9) * 0.5 + 0.5) : 1.0;

    // Cockpit plate.
    final plate = chamferPath(
      const Rect.fromLTWH(_left, _top, _barW, _barH),
      9,
    );
    drawGlow(canvas, plate, low ? HudColors.warn : HudColors.cyan,
        low ? 0.6 * blink : 0.25);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, HudColors.cyan.withValues(alpha: 0.7), 1.4);

    final label = _fuelLabel.layout(
      TextSpan(text: 'FUEL', style: hudFont(9, const Color(0xB3FFFFFF))),
    );
    label.paint(
      canvas,
      Offset(_left + 10, _top + (_barH - label.height) / 2),
    );

    // Segmented cells.
    const innerLeft = _left + 46;
    const innerW = _barW - 46 - 8;
    const innerTop = _top + 7;
    const innerH = _barH - 14;
    const gap = 2.0;
    const cellW = (innerW - gap * (_segments - 1)) / _segments;
    final lit = fuelFraction.clamp(0.0, 1.0) * _segments;
    final on = Paint()..color = fillColor.withValues(alpha: blink);
    final off = Paint()..color = const Color(0x1FFFFFFF);
    for (var i = 0; i < _segments; i++) {
      final x = innerLeft + i * (cellW + gap);
      final cell = Rect.fromLTWH(x, innerTop, cellW, innerH);
      canvas.drawRect(cell, off);
      if (i < lit) {
        final w = cellW * math.min(1.0, lit - i);
        canvas.drawRect(Rect.fromLTWH(x, innerTop, w, innerH), on);
      }
    }

    // Star thresholds: a tick per mark, lit while fuel is still above it.
    for (final mark in starMarks) {
      final x = innerLeft + innerW * mark;
      final kept = fuelFraction >= mark;
      canvas.drawLine(
        Offset(x, innerTop - 3),
        Offset(x, innerTop + innerH + 3),
        Paint()
          ..color = kept ? const Color(0xFFFFD166) : const Color(0x66FFFFFF)
          ..strokeWidth = 2,
      );
    }

    if (_costLeft > 0) _drawCost(canvas, innerLeft, innerW, innerTop, innerH);

    if (low) {
      final tp = _lowLabel.layout(
        TextSpan(
          text: 'LOW FUEL',
          style: hudFont(
            11,
            HudColors.warn.withValues(alpha: quantizeAlpha(blink)),
            spacing: 1.5,
          ),
        ),
      );
      tp.paint(
        canvas,
        Offset(_left + _barW + 24, innerTop + innerH / 2 - tp.height / 2),
      );
    }

    // Tow indicator: a lit hex beside the gauge.
    if (towing) {
      const towC = Offset(_left + _barW + 10, _top + _barH / 2);
      final hex = hexPath(towC, 4.5);
      drawGlow(canvas, hex, HudColors.green, 0.8);
      canvas.drawPath(hex, Paint()..color = HudColors.green);
    }
  }

  /// The burnt slice flashes at the fill edge with '−0.5%' beside it.
  void _drawCost(
    Canvas canvas,
    double innerLeft,
    double innerW,
    double innerTop,
    double innerH,
  ) {
    final a = (_costLeft / _costSeconds).clamp(0.0, 1.0);
    final edge = innerLeft + innerW * fuelFraction.clamp(0.0, 1.0);
    final slice = math.max(3.0, innerW * _costFrac);
    final burnt = Rect.fromLTWH(edge, innerTop - 1, slice, innerH + 2);
    canvas.drawRect(
      burnt,
      Paint()..color = Color.lerp(HudColors.thrust, Colors.white, a * 0.5)!
          .withValues(alpha: 0.9 * a),
    );
    final pct = _costFrac * 100;
    final text = '−${pct < 1 ? pct.toStringAsFixed(1) : pct.round()}%';
    final tp = _costLabel.layout(
      TextSpan(text: text, style: hudFont(9, HudColors.thrustHot.withValues(alpha: quantizeAlpha(a)), spacing: 0.6)),
    );
    // In the empty part of the bar when it fits, else over the lit cells.
    final right = innerLeft + innerW;
    final x = edge + slice + 4 + tp.width <= right
        ? edge + slice + 4
        : edge - 4 - tp.width;
    final y = innerTop + (innerH - tp.height) / 2;
    canvas.drawRect(
      Rect.fromLTWH(x - 2, y, tp.width + 4, tp.height),
      Paint()..color = HudColors.plateDark.withValues(alpha: 0.9 * a),
    );
    tp.paint(canvas, Offset(x, y));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compass / level info strip
// ─────────────────────────────────────────────────────────────────────────────

/// Level label + best stars, then a live timer and the best star target
/// still reachable this flight (fuel and time only ever get worse, so a lost
/// target never comes back). Sits under the fuel gauge, top-left.
class LevelInfoHud extends PositionComponent {
  LevelInfoHud() : super(priority: 4900);

  final _lineText = HudText();
  final _labelText = HudText();

  String levelLabel = '';
  int stars = 0;

  double elapsed = 0;
  double fuelFraction = 1;
  StarSpec starSpec = const StarSpec();


  /// Outline the target line (the comms is explaining the star rules).
  bool frameTarget = false;
  double _frame = 0;
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _frame = (_frame + (frameTarget ? dt : -dt) * 4).clamp(0.0, 1.0);
  }

  @override
  void render(Canvas canvas) {
    if (levelLabel.isEmpty) return;

    final tp = _labelText.layout(
      TextSpan(
        text: levelLabel,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
        ),
      ),
    );
    const left = 12.0;
    const top = 40.0;
    tp.paint(canvas, const Offset(left, top));

    var starX = left + tp.width + 8;
    for (int i = 0; i < 3; i++) {
      _drawStar(
        canvas,
        Offset(starX + 7, top + tp.height / 2),
        6,
        i < stars ? HudColors.star : const Color(0x55FFFFFF),
      );
      starX += 16;
    }

    final (targetStars, hint, color) = _target();
    final line = _lineText.layout(
      TextSpan(
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
        ),
        children: [
          TextSpan(
            text: _fmt(elapsed),
            style: const TextStyle(color: Color(0xCCFFFFFF)),
          ),
          const TextSpan(text: '   '),
          TextSpan(text: '★' * targetStars, style: TextStyle(color: color)),
          TextSpan(text: '  $hint', style: TextStyle(color: color.withValues(alpha: 0.85))),
        ],
      ),
    );
    final lineTop = top + tp.height + 3;
    line.paint(canvas, Offset(left, lineTop));
    if (_frame > 0) {
      final pulse = 0.6 + 0.4 * math.sin(_t * 5);
      final frame = chamferPath(
        Rect.fromLTWH(left - 6, lineTop - 3, line.width + 12, line.height + 6),
        6,
      );
      drawGlow(canvas, frame, HudColors.star, 0.5 * _frame * pulse);
      drawStroke(canvas, frame, HudColors.star.withValues(alpha: 0.85 * _frame * pulse), 1.3);
    }
  }

  (int, String, Color) _target() {
    final s = starSpec;
    if (s.earnsThree(fuelFraction, elapsed)) {
      final left = (s.star3Time - elapsed).ceil();
      return (3, 'keep ≥${(s.star3Fuel * 100).round()}% fuel · ${left}s left', HudColors.star);
    }
    if (s.earnsTwo(fuelFraction)) {
      return (2, 'keep ≥${(s.star2Fuel * 100).round()}% fuel', const Color(0xFFE0E0E0));
    }
    return (1, 'deliver the cargo', const Color(0xFFB0B0B0));
  }

  static String _fmt(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$sec';
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color color) =>
      canvas.drawPath(starPath(center, size), Paint()..color = color);
}

/// Local gravity readout next to the fuel gauge: an arrow pointing where the
/// ship is being pulled (length ∝ strength) plus "0.6g". Shown only on levels
/// whose gravity differs from normal, so standard levels stay uncluttered.
class GravityIndicatorHud extends PositionComponent {
  GravityIndicatorHud() : super(priority: 4900);

  final _gText = HudText();

  bool show = false;

  /// Local acceleration at the ship in g (+Y down).
  final Vector2 accelG = Vector2(0, 1);

  /// Theme accent for the arrow.
  Color accent = const Color(0xFF00B4D8);

  static const double _cx = 258;
  static const double _cy = 21;
  static const double _r = 15;

  @override
  void render(Canvas canvas) {
    if (!show) return;
    const center = Offset(_cx, _cy);
    final hex = hexPath(center, _r + 1);
    canvas.drawPath(hex, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, hex, accent.withValues(alpha: 0.7), 1.4);

    final g = accelG.length;
    if (g < 0.03) {
      // Zero-g: a hollow dot instead of an arrow.
      canvas.drawCircle(
        center,
        3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accent,
      );
    } else {
      final len = (_r - 3) * (0.35 + 0.65 * (g / 2.5).clamp(0.0, 1.0));
      final dir = Offset(accelG.x / g, accelG.y / g);
      final tip = center + dir * len;
      final tail = center - dir * (len * 0.6);
      final paint = Paint()
        ..color = accent
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, tip, paint);
      final side = Offset(-dir.dy, dir.dx) * 3.5;
      final back = tip - dir * 5;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(back.dx + side.dx, back.dy + side.dy)
          ..lineTo(back.dx - side.dx, back.dy - side.dy)
          ..close(),
        Paint()..color = accent,
      );
    }

    final tp = _gText.layout(
      TextSpan(
        text: '${g.toStringAsFixed(g < 0.95 || g > 1.05 ? 1 : 0)}g',
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
        ),
      ),
    );
    tp.paint(canvas, Offset(_cx + _r + 5, _cy - tp.height / 2));
  }
}
