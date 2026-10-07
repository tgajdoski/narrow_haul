import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

/// On-screen controls for landscape play.
///
/// Left 50% of screen → [_FloatingJoystick]: appears where the thumb lands.
/// Horizontal axis [-1..1] drives rotation.
///
/// Right side → [_ThrustButton]: large circular hold-button for engine thrust.
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateAxis,
    required this.onThrust,
  }) : super(priority: 5000);

  final void Function(double axis) onRotateAxis;
  final void Function(bool pressed) onThrust;

  /// Mirror the layout: thrust bottom-left, joystick on the right half.
  bool get leftHanded => _leftHanded;
  bool _leftHanded = false;
  set leftHanded(bool v) {
    if (v == _leftHanded) return;
    _leftHanded = v;
    _relayout(size);
  }

  _FloatingJoystick? _joystick;
  _ThrustButton? _thrustBtn;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.topLeft;
    position = Vector2.zero();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    _relayout(size);
  }

  void _relayout(Vector2 sz) {
    if (sz.x <= 0 || sz.y <= 0) return;

    _joystick?.removeFromParent();
    _thrustBtn?.removeFromParent();

    _joystick = _FloatingJoystick(
      areaSize: Vector2(sz.x * 0.5, sz.y),
      position: Vector2(_leftHanded ? sz.x * 0.5 : 0, 0),
      onAxisChanged: onRotateAxis,
      hintFraction: _leftHanded ? 0.78 : 0.22,
    );

    const btnRadius = 52.0;
    const margin = 28.0;
    final btnX = _leftHanded ? margin + btnRadius : sz.x - margin - btnRadius;
    _thrustBtn = _ThrustButton(
      center: Vector2(btnX, sz.y - margin - btnRadius),
      radius: btnRadius,
      onChanged: onThrust,
    );

    add(_joystick!);
    add(_thrustBtn!);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Joystick
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingJoystick extends PositionComponent with DragCallbacks {
  _FloatingJoystick({
    required Vector2 areaSize,
    required Vector2 position,
    required this.onAxisChanged,
    this.hintFraction = 0.22,
  }) : super(
          position: position,
          size: areaSize,
          anchor: Anchor.topLeft,
        );

  final void Function(double axis) onAxisChanged;

  /// Horizontal position of the idle hint within the joystick area.
  final double hintFraction;

  static const double _maxKnobRadius = 56.0;
  static const double _baseOuterRadius = 68.0;
  static const double _knobRadius = 28.0;
  static const double _deadzone = 0.06;

  int? _trackingPointerId;
  Vector2? _baseCenter;
  Vector2? _knobCenter;
  bool _active = false;

  Sprite? _baseSprite;
  Sprite? _knobSprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _baseSprite = await Sprite.load('joystick_base.png');
    } catch (_) {}
    try {
      _knobSprite = await Sprite.load('joystick_knob.png');
    } catch (_) {}
  }

  void _emit(double raw) {
    final clamped = raw.clamp(-1.0, 1.0);
    onAxisChanged(clamped.abs() < _deadzone ? 0.0 : clamped);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_trackingPointerId != null) return;
    _trackingPointerId = event.pointerId;
    _baseCenter = event.localPosition.clone();
    _knobCenter = _baseCenter!.clone();
    _active = true;
    _emit(0);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (event.pointerId != _trackingPointerId) return;
    final base = _baseCenter!;
    final delta = event.localEndPosition - base;
    final dx = delta.x.clamp(-_maxKnobRadius, _maxKnobRadius);
    final dy = delta.y.clamp(-_maxKnobRadius, _maxKnobRadius);
    _knobCenter = base + Vector2(dx, dy);
    _emit(dx / _maxKnobRadius);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _trackingPointerId) return;
    _reset();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId != _trackingPointerId) return;
    _reset();
  }

  void _reset() {
    _trackingPointerId = null;
    _baseCenter = null;
    _knobCenter = null;
    _active = false;
    _emit(0);
  }

  @override
  void render(Canvas canvas) {
    if (_active) {
      _drawJoystick(canvas);
    } else {
      _drawHint(canvas);
    }
  }

  /// Resting position hint: show the full joystick (base + centred knob)
  /// at a fixed bottom-left location so the player always sees it.
  void _drawHint(Canvas canvas) {
    final cx = size.x * hintFraction;
    final cy = size.y - _baseOuterRadius - 16;

    if (_baseSprite != null) {
      final d = _baseOuterRadius * 2;
      _baseSprite!.render(
        canvas,
        position: Vector2(cx - _baseOuterRadius, cy - _baseOuterRadius),
        size: Vector2(d, d),
      );
    } else {
      _drawFallbackBase(canvas, Vector2(cx, cy));
    }

    if (_knobSprite != null) {
      final kd = _knobRadius * 2;
      _knobSprite!.render(
        canvas,
        position: Vector2(cx - _knobRadius, cy - _knobRadius),
        size: Vector2(kd, kd),
      );
    } else {
      _drawFallbackKnob(canvas, Vector2(cx, cy));
    }
  }

  void _drawJoystick(Canvas canvas) {
    final base = _baseCenter!;
    final knob = _knobCenter!;
    final baseDiam = _baseOuterRadius * 2;
    final knobDiam = _knobRadius * 2;

    if (_baseSprite != null) {
      _baseSprite!.render(
        canvas,
        position: Vector2(base.x - _baseOuterRadius, base.y - _baseOuterRadius),
        size: Vector2(baseDiam, baseDiam),
      );
    } else {
      _drawFallbackBase(canvas, base);
    }

    if (_knobSprite != null) {
      _knobSprite!.render(
        canvas,
        position: Vector2(knob.x - _knobRadius, knob.y - _knobRadius),
        size: Vector2(knobDiam, knobDiam),
      );
    } else {
      _drawFallbackKnob(canvas, knob);
    }
  }

  void _drawFallbackBase(Canvas canvas, Vector2 base) {
    canvas.drawCircle(
      Offset(base.x, base.y),
      _baseOuterRadius,
      Paint()..color = const Color(0x331B263B),
    );
    canvas.drawCircle(
      Offset(base.x, base.y),
      _baseOuterRadius,
      Paint()
        ..color = const Color(0xAA00B4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      Offset(base.x, base.y),
      _maxKnobRadius,
      Paint()
        ..color = const Color(0x2200B4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawFallbackKnob(Canvas canvas, Vector2 knob) {
    canvas.drawCircle(
      Offset(knob.x + 2, knob.y + 2),
      _knobRadius,
      Paint()..color = const Color(0x44000000),
    );
    canvas.drawCircle(
      Offset(knob.x, knob.y),
      _knobRadius,
      Paint()..color = const Color(0xFF00B4D8),
    );
    canvas.drawCircle(
      Offset(knob.x - 5, knob.y - 5),
      _knobRadius * 0.5,
      Paint()..color = const Color(0x4487E8FF),
    );
    canvas.drawCircle(
      Offset(knob.x, knob.y),
      _knobRadius,
      Paint()
        ..color = const Color(0xCC87E8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thrust Button
// ─────────────────────────────────────────────────────────────────────────────

class _ThrustButton extends PositionComponent with DragCallbacks, TapCallbacks {
  _ThrustButton({
    required Vector2 center,
    required this.radius,
    required this.onChanged,
  }) : super(
          position: center - Vector2.all(radius),
          size: Vector2.all(radius * 2),
          anchor: Anchor.topLeft,
        );

  final double radius;
  final void Function(bool pressed) onChanged;

  bool _pressed = false;
  int? _pointerId;

  Sprite? _idleSprite;
  Sprite? _pressedSprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _idleSprite = await Sprite.load('thrust_idle.png');
    } catch (_) {}
    try {
      _pressedSprite = await Sprite.load('thrust_press.png');
    } catch (_) {}
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _press(event.pointerId);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _pointerId) return;
    _release();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId != _pointerId) return;
    _release();
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    _press(null);
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (_pointerId != null && event.pointerId != _pointerId) return;
    _release();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    if (_pointerId != null && event.pointerId != _pointerId) return;
    _release();
  }

  void _press(int? pointerId) {
    if (_pressed) return;
    _pointerId = pointerId;
    _pressed = true;
    onChanged(true);
  }

  void _release() {
    if (!_pressed) return;
    _pointerId = null;
    _pressed = false;
    onChanged(false);
  }

  @override
  void render(Canvas canvas) {
    final sprite = _pressed ? (_pressedSprite ?? _idleSprite) : _idleSprite;
    if (sprite != null) {
      sprite.render(
        canvas,
        position: Vector2.zero(),
        size: Vector2(radius * 2, radius * 2),
      );
      return;
    }
    _drawFallback(canvas);
  }

  void _drawFallback(Canvas canvas) {
    final cx = radius;
    final cy = radius;
    final alpha = _pressed ? 1.0 : 0.72;

    if (_pressed) {
      canvas.drawCircle(
        Offset(cx, cy),
        radius + 8,
        Paint()
          ..color = const Color(0x33FF6B35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()..color = Color.fromARGB((_pressed ? 220 : 80).round(), 27, 38, 59),
    );

    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = Color.fromARGB(
          (255 * alpha).round(),
          _pressed ? 0xFF : 0xE0,
          _pressed ? 0x6B : 0xA0,
          _pressed ? 0x35 : 0x50,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = _pressed ? 3.5 : 2.5,
    );

    _drawFlameIcon(canvas, Offset(cx, cy), radius * 0.55, alpha);
    _drawLabel(canvas, Offset(cx, cy + radius * 0.62), alpha);
  }

  void _drawFlameIcon(Canvas canvas, Offset center, double size, double alpha) {
    final baseColor = _pressed ? const Color(0xFFFF6B35) : const Color(0xFFE07A5F);
    final paint = Paint()
      ..color = Color.fromARGB(
        (255 * alpha).round(),
        (baseColor.r * 255).round(),
        (baseColor.g * 255).round(),
        (baseColor.b * 255).round(),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(center.dx - size * 0.4, center.dy + size * 0.55);
    path.cubicTo(
      center.dx - size * 0.5, center.dy - size * 0.1,
      center.dx - size * 0.1, center.dy - size * 0.8,
      center.dx, center.dy - size,
    );
    path.cubicTo(
      center.dx + size * 0.1, center.dy - size * 0.8,
      center.dx + size * 0.5, center.dy - size * 0.1,
      center.dx + size * 0.4, center.dy + size * 0.55,
    );
    canvas.drawPath(path, paint);

    if (_pressed) {
      canvas.drawCircle(
        Offset(center.dx, center.dy - size * 0.2),
        size * 0.18,
        Paint()..color = const Color(0xFFFFD166),
      );
    }
  }

  void _drawLabel(Canvas canvas, Offset pos, double alpha) {
    final linePaint = Paint()
      ..color = Color.fromARGB((180 * alpha).round(), 255, 255, 255)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 3; i++) {
      final y = pos.dy + (i - 1) * 4.0;
      final w = (i == 1) ? 18.0 : 12.0;
      canvas.drawLine(Offset(pos.dx - w / 2, y), Offset(pos.dx + w / 2, y), linePaint);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fuel gauge bar (rendered in HUD layer over game world)
// ─────────────────────────────────────────────────────────────────────────────

/// A horizontal fuel gauge drawn directly to viewport canvas.
class FuelGaugeHud extends PositionComponent {
  FuelGaugeHud() : super(priority: 4900);

  double fuelFraction = 1.0;
  bool towing = false;

  /// Fuel fractions needed for 3★ / 2★ — drawn as ticks on the bar.
  List<double> starMarks = const [];

  static const double lowFuel = 0.15;
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  Sprite? _frameSprite;

  static const double _barW = 220.0;
  static const double _barH = 26.0;
  static const double _left = 12.0;
  static const double _top = 8.0;
  static const double _fillInset = 5.0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _frameSprite = await Sprite.load('fuel_bar.png');
    } catch (_) {}
  }

  @override
  void render(Canvas canvas) {
    final fillColor = fuelFraction > 0.4
        ? const Color(0xFF00B4D8)
        : fuelFraction > 0.15
            ? const Color(0xFFFFD166)
            : const Color(0xFFFF6B35);
    // Low fuel: the fill blinks so it's noticed in peripheral vision.
    final low = fuelFraction > 0 && fuelFraction < lowFuel;
    final blink = low ? 0.35 + 0.65 * (math.sin(_t * 9) * 0.5 + 0.5) : 1.0;
    final fillPaint = Paint()..color = fillColor.withValues(alpha: blink);
    final double innerLeft;
    final double innerW;
    final double innerTop;
    final double innerH;

    if (_frameSprite != null) {
      // Sprite-based frame
      _frameSprite!.render(
        canvas,
        position: Vector2(_left, _top),
        size: Vector2(_barW, _barH),
      );

      // Dynamic fill drawn inside the frame
      if (fuelFraction > 0) {
        final fillW = (_barW - _fillInset * 2) * fuelFraction;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(_left + _fillInset, _top + _fillInset, fillW, _barH - _fillInset * 2),
            const Radius.circular(3),
          ),
          fillPaint,
        );
      }
      innerLeft = _left + _fillInset;
      innerW = _barW - _fillInset * 2;
      innerTop = _top + _fillInset;
      innerH = _barH - _fillInset * 2;
    } else {
      // Fallback: pure canvas bar
      const barW = 120.0;
      const barH = 8.0;
      const left = 12.0;
      const top = 10.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(left, top, barW, barH),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0x441B263B),
      );

      if (fuelFraction > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, barW * fuelFraction, barH),
            const Radius.circular(4),
          ),
          fillPaint,
        );
      }
      innerLeft = left;
      innerW = barW;
      innerTop = top;
      innerH = barH;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(left, top, barW, barH),
          const Radius.circular(4),
        ),
        Paint()
          ..color = const Color(0x8800B4D8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Star thresholds: a tick per mark, lit while fuel is still above it.
    for (final mark in starMarks) {
      final x = innerLeft + innerW * mark;
      final kept = fuelFraction >= mark;
      canvas.drawLine(
        Offset(x, innerTop - 2),
        Offset(x, innerTop + innerH + 2),
        Paint()
          ..color = kept ? const Color(0xFFFFD166) : const Color(0x66FFFFFF)
          ..strokeWidth = 2,
      );
    }

    if (low) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'LOW FUEL',
          style: TextStyle(
            color: const Color(0xFFFF6B35).withValues(alpha: blink),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (_frameSprite != null ? _left + _barW : 12.0 + 120.0) + 24;
      tp.paint(canvas, Offset(x, innerTop + innerH / 2 - tp.height / 2));
    }

    // Tow indicator dot (always code-drawn)
    if (towing) {
      final towX = _frameSprite != null ? _left + _barW + 10 : 12.0 + 120.0 + 10;
      const towY = _top + _barH / 2;
      canvas.drawCircle(
        Offset(towX, towY),
        4,
        Paint()..color = const Color(0xFF4ADE80),
      );
      canvas.drawCircle(
        Offset(towX, towY),
        4,
        Paint()
          ..color = const Color(0xFF4ADE80)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
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

  String levelLabel = '';
  int stars = 0;

  double elapsed = 0;
  double fuelFraction = 1;
  double star3Fuel = 0.7;
  double star2Fuel = 0.4;
  double star3Time = 60;

  static const _gold = Color(0xFFFFD166);

  @override
  void render(Canvas canvas) {
    if (levelLabel.isEmpty) return;

    final tp = TextPainter(
      text: TextSpan(
        text: levelLabel,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const left = 12.0;
    const top = 40.0;
    tp.paint(canvas, const Offset(left, top));

    var starX = left + tp.width + 8;
    for (int i = 0; i < 3; i++) {
      _drawStar(
        canvas,
        Offset(starX + 7, top + tp.height / 2),
        6,
        i < stars ? _gold : const Color(0x55FFFFFF),
      );
      starX += 16;
    }

    final (targetStars, hint, color) = _target();
    final line = TextPainter(
      text: TextSpan(
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
      textDirection: TextDirection.ltr,
    )..layout();
    line.paint(canvas, Offset(left, top + tp.height + 3));
  }

  (int, String, Color) _target() {
    final pct3 = (star3Fuel * 100).round();
    if (fuelFraction >= star3Fuel && elapsed <= star3Time) {
      final left = (star3Time - elapsed).ceil();
      return (3, 'keep ≥$pct3% fuel · ${left}s left', _gold);
    }
    if (fuelFraction >= star2Fuel) {
      return (2, 'keep ≥${(star2Fuel * 100).round()}% fuel', const Color(0xFFE0E0E0));
    }
    return (1, 'deliver the cargo', const Color(0xFFB0B0B0));
  }

  static String _fmt(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$sec';
  }

  void _drawStar(Canvas canvas, Offset center, double size, Color color) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2 + (i * 2 * math.pi / 5);
      final innerAngle = outerAngle + math.pi / 5;
      final outerX = center.dx + size * math.cos(outerAngle);
      final outerY = center.dy + size * math.sin(outerAngle);
      final innerX = center.dx + size * 0.4 * math.cos(innerAngle);
      final innerY = center.dy + size * 0.4 * math.sin(innerAngle);
      if (i == 0) {
        path.moveTo(outerX, outerY);
      } else {
        path.lineTo(outerX, outerY);
      }
      path.lineTo(innerX, innerY);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }
}

/// Local gravity readout next to the fuel gauge: an arrow pointing where the
/// ship is being pulled (length ∝ strength) plus "0.6g". Shown only on levels
/// whose gravity differs from normal, so standard levels stay uncluttered.
class GravityIndicatorHud extends PositionComponent {
  GravityIndicatorHud() : super(priority: 4900);

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
    canvas.drawCircle(center, _r, Paint()..color = const Color(0xAA0D1B2A));
    canvas.drawCircle(
      center,
      _r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.6),
    );

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

    final tp = TextPainter(
      text: TextSpan(
        text: '${g.toStringAsFixed(g < 0.95 || g > 1.05 ? 1 : 0)}g',
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(_cx + _r + 5, _cy - tp.height / 2));
  }
}
