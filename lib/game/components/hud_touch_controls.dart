import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

/// On-screen controls for landscape play.
///
/// Left 50% of screen → [_FloatingJoystick]: appears where the thumb lands.
/// Horizontal axis [-1..1] drives rotation.
///
/// Right side → [_ThrustButton]: large circular hold-button for engine thrust.
/// Armed ships add [_FireButton] above it (tap = one shot, hold = auto-fire).
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateAxis,
    required this.onThrust,
    this.onFire,
    this.onCycleWeapon,
  }) : super(priority: 5000);

  final void Function(double axis) onRotateAxis;
  final void Function(bool pressed) onThrust;
  final void Function(bool pressed)? onFire;

  /// Tap on the weapon chip: next weapon.
  final void Function()? onCycleWeapon;

  /// What the FIRE button fires, e.g. ('BOMB', '×3', true); null = the
  /// plain cannon. The flag says whether there's another weapon to cycle to.
  (String label, String? count, bool canCycle)? weapon;

  /// Show the FIRE button (only for armed ships).
  bool get showFire => _showFire;
  bool _showFire = false;
  set showFire(bool v) {
    if (v == _showFire) return;
    _showFire = v;
    _relayout(size);
  }

  /// Mirror the layout: thrust bottom-left, joystick on the right half.
  bool get leftHanded => _leftHanded;
  bool _leftHanded = false;
  set leftHanded(bool v) {
    if (v == _leftHanded) return;
    _leftHanded = v;
    _relayout(size);
  }

  /// Safe-area insets: buttons and the joystick hint stay clear of them.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;
  set insets(EdgeInsets v) {
    if (v == _insets) return;
    _insets = v;
    _relayout(size);
  }

  _FloatingJoystick? _joystick;
  _ThrustButton? _thrustBtn;
  _FireButton? _fireBtn;
  _WeaponChip? _chip;

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
    if (_fireBtn?.pressed == true) onFire?.call(false);
    _fireBtn?.removeFromParent();
    _fireBtn = null;
    _chip?.removeFromParent();
    _chip = null;

    _joystick = _FloatingJoystick(
      areaSize: Vector2(sz.x * 0.5, sz.y),
      position: Vector2(_leftHanded ? sz.x * 0.5 : 0, 0),
      onAxisChanged: onRotateAxis,
      hintFraction: _leftHanded ? 0.78 : 0.22,
      // The joystick covers one half: only that half's outer edge is inset.
      hintInsets: _leftHanded
          ? EdgeInsets.only(right: _insets.right, bottom: _insets.bottom)
          : EdgeInsets.only(left: _insets.left, bottom: _insets.bottom),
    );

    const btnRadius = 52.0;
    const margin = 28.0;
    final btnX = _leftHanded
        ? _insets.left + margin + btnRadius
        : sz.x - _insets.right - margin - btnRadius;
    final btnY = sz.y - _insets.bottom - margin - btnRadius;
    _thrustBtn = _ThrustButton(
      center: Vector2(btnX, btnY),
      radius: btnRadius,
      onChanged: onThrust,
    );

    add(_joystick!);
    add(_thrustBtn!);

    if (_showFire && onFire != null) {
      // Directly above thrust: the same thumb rocks between the two.
      const fireRadius = 40.0;
      final fireCenter = Vector2(btnX, btnY - btnRadius - 18 - fireRadius);
      _fireBtn = _FireButton(
        center: fireCenter,
        radius: fireRadius,
        onChanged: onFire!,
        weapon: () => weapon,
      );
      add(_fireBtn!);
      // Weapon chip beside FIRE, on the screen-centre side.
      const chipW = 74.0;
      const chipH = 30.0;
      final side = _leftHanded ? 1.0 : -1.0;
      _chip = _WeaponChip(
        position: Vector2(
          fireCenter.x + side * (fireRadius + 12 + chipW / 2) - chipW / 2,
          fireCenter.y - chipH / 2,
        ),
        size: Vector2(chipW, chipH),
        weapon: () => weapon,
        onTap: () => onCycleWeapon?.call(),
      );
      add(_chip!);
    }
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
    this.hintInsets = EdgeInsets.zero,
  }) : super(
          position: position,
          size: areaSize,
          anchor: Anchor.topLeft,
        );

  final void Function(double axis) onAxisChanged;

  /// Horizontal position of the idle hint within the joystick area.
  final double hintFraction;

  /// Keeps the idle hint clear of the notch / home indicator.
  final EdgeInsets hintInsets;

  static const double _maxKnobRadius = 56.0;
  static const double _baseOuterRadius = 68.0;
  static const double _knobRadius = 28.0;
  static const double _deadzone = FlightTuning.stickDeadzone;

  int? _trackingPointerId;
  Vector2? _baseCenter;
  Vector2? _knobCenter;
  bool _active = false;

  /// Last emitted axis, for lighting the side the pilot is turning to.
  double _axis = 0;

  void _emit(double raw) {
    final clamped = raw.clamp(-1.0, 1.0);
    _axis = clamped.abs() < _deadzone ? 0.0 : clamped;
    onAxisChanged(_axis);
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

  /// Resting position hint: the full dial (base + centred knob) at a fixed
  /// bottom corner so the player always sees where to steer.
  void _drawHint(Canvas canvas) {
    const edge = _baseOuterRadius + 12;
    final cx = (size.x * hintFraction).clamp(
      hintInsets.left + edge,
      math.max(hintInsets.left + edge, size.x - hintInsets.right - edge),
    ).toDouble();
    final cy = size.y - hintInsets.bottom - _baseOuterRadius - 16;
    final c = Offset(cx, cy);
    _drawBase(canvas, c, active: false);
    _drawKnob(canvas, c, active: false);
  }

  void _drawJoystick(Canvas canvas) {
    final base = _baseCenter!;
    final knob = _knobCenter!;
    _drawBase(canvas, Offset(base.x, base.y), active: true);
    _drawKnob(canvas, Offset(knob.x, knob.y), active: true);
  }

  /// Rotation dial: ring with ticks, a horizontal track lit toward the
  /// current turn, and curved arrows that light on the side being turned to.
  void _drawBase(Canvas canvas, Offset c, {required bool active}) {
    const r = _baseOuterRadius;
    final a = active ? 1.0 : 0.6;
    final axis = active ? _axis : 0.0;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = HudColors.plate.withValues(alpha: active ? 0.7 : 0.4),
    );
    final ring = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    drawGlow(canvas, ring, HudColors.cyan, active ? 0.45 : 0.12);
    drawStroke(canvas, ring, HudColors.cyan.withValues(alpha: 0.75 * a), 1.6);

    final tick = Paint()
      ..color = HudColors.cyan.withValues(alpha: 0.35 * a)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 36; i++) {
      final ang = i * math.pi / 18;
      final d = Offset(math.cos(ang), math.sin(ang));
      final major = i % 9 == 0;
      canvas.drawLine(c + d * (r - (major ? 11 : 6)), c + d * (r - 3), tick);
    }

    canvas.drawLine(
      c + const Offset(-_maxKnobRadius, 0),
      c + const Offset(_maxKnobRadius, 0),
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // Boost zone: gold notches where the precise zone ends.
    const boostX = FlightTuning.boostStart * _maxKnobRadius;
    final notch = Paint()
      ..color = HudColors.gold.withValues(alpha: 0.55 * a)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final side in const [-1.0, 1.0]) {
      final x = c.dx + side * boostX;
      canvas.drawLine(Offset(x, c.dy - 7), Offset(x, c.dy + 7), notch);
    }
    final boosting = FlightTuning.stickBoosting(axis);
    if (axis != 0) {
      final lit = Paint()
        ..color = HudColors.cyanBright.withValues(alpha: 0.85)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final reach = axis.sign * math.min(axis.abs(), FlightTuning.boostStart);
      canvas.drawLine(c, c + Offset(reach * _maxKnobRadius, 0), lit);
      if (boosting) {
        canvas.drawLine(
          c + Offset(axis.sign * boostX, 0),
          c + Offset(axis * _maxKnobRadius, 0),
          lit..color = HudColors.gold,
        );
      }
    }
    _drawTurnArrow(canvas, c, left: true, lit: axis < 0, boost: boosting, alpha: a);
    _drawTurnArrow(canvas, c, left: false, lit: axis > 0, boost: boosting, alpha: a);
  }

  void _drawTurnArrow(
    Canvas canvas,
    Offset c, {
    required bool left,
    required bool lit,
    required double alpha,
    bool boost = false,
  }) {
    const r = _baseOuterRadius * 0.7;
    final start = left ? -math.pi * 0.62 : -math.pi * 0.38;
    final sweep = left ? -0.5 : 0.5;
    final color = lit
        ? (boost ? HudColors.gold : HudColors.cyanBright)
        : HudColors.cyan.withValues(alpha: 0.45 * alpha);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = lit ? (boost ? 4 : 3) : 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false, paint);
    final end = start + sweep;
    final tip = c + Offset(math.cos(end), math.sin(end)) * r;
    final tangent = Offset(-math.sin(end), math.cos(end)) * sweep.sign;
    final normal = Offset(-tangent.dy, tangent.dx);
    canvas.drawLine(tip, tip - tangent * 7 + normal * 5, paint);
    canvas.drawLine(tip, tip - tangent * 7 - normal * 5, paint);
  }

  /// Hexagonal puck with a glowing core.
  void _drawKnob(Canvas canvas, Offset c, {required bool active}) {
    const r = _knobRadius;
    final hex = hexPath(c, r);
    drawGlow(canvas, hex, HudColors.cyanBright, active ? 0.9 : 0.3);
    canvas.drawPath(
      hex,
      Paint()
        ..shader = RadialGradient(
          colors: active
              ? const [HudColors.cyanBright, HudColors.cyan, Color(0xFF075A73)]
              : const [Color(0xCC5CE1FF), Color(0xAA00B4D8), Color(0x88075A73)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    drawStroke(canvas, hex, Colors.white.withValues(alpha: active ? 0.9 : 0.5), 1.4);
    drawStroke(
      canvas,
      hexPath(c, r * 0.48),
      Colors.white.withValues(alpha: active ? 0.55 : 0.3),
      1.2,
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

  /// Seconds alive (pulse rings) and 0–1 smoothed press state.
  double _t = 0;
  double _heat = 0;
  final _thrustLabel = HudText();

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _heat += ((_pressed ? 1.0 : 0.0) - _heat) * math.min(1.0, dt * 14);
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
    _drawPad(canvas, HudColors.thrust, flatTop: true);
    final c = Offset(radius, radius);
    final flicker = _pressed ? 1 + 0.07 * math.sin(_t * 42) : 1.0;
    drawFlameGlyph(
      canvas,
      c + Offset(0, -radius * 0.12),
      radius * 0.6 * flicker,
      hot: _pressed,
    );
    final tp = _thrustLabel.layout(
      TextSpan(
        text: 'THRUST',
        style: hudFont(
          9.5,
          Colors.white.withValues(alpha: 0.55 + 0.4 * _heat),
          spacing: 1.8,
        ),
      ),
    );
    tp.paint(canvas, Offset(radius - tp.width / 2, radius + radius * 0.42));
  }

  /// Hexagonal pad: pulse rings while held, glow, heated fill, rim and
  /// corner ticks, all in [accent].
  void _drawPad(Canvas canvas, Color accent, {required bool flatTop}) {
    final c = Offset(radius, radius);
    final rot = flatTop ? math.pi / 6 : 0.0;
    final hex = hexPath(c, radius, rotation: rot);

    if (_heat > 0.05) {
      for (var k = 0; k < 2; k++) {
        final phase = (_t * 1.8 + k * 0.5) % 1.0;
        drawStroke(
          canvas,
          hexPath(c, radius * (1 + 0.35 * phase), rotation: rot),
          accent.withValues(alpha: (1 - phase) * 0.45 * _heat),
          2,
        );
      }
    }
    drawGlow(canvas, hex, accent, 0.2 + 0.8 * _heat);
    canvas.drawPath(
      hex,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(HudColors.plate, accent.withValues(alpha: 0.75), _heat)!,
            Color.lerp(HudColors.plateDark, const Color(0xE61A0C06), _heat)!,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    drawStroke(
      canvas,
      hex,
      accent.withValues(alpha: 0.65 + 0.35 * _heat),
      2 + 1.2 * _heat,
    );
    drawStroke(
      canvas,
      hexPath(c, radius * 0.82, rotation: rot),
      accent.withValues(alpha: 0.18 + 0.2 * _heat),
      1,
    );
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 + 0.5 * _heat)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = rot + math.pi / 6 + i * math.pi / 3;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (radius * 0.86), c + d * (radius * 0.97), tick);
    }
  }
}

/// Cannon trigger: the thrust button's touch handling with a crosshair face.
class _FireButton extends _ThrustButton {
  _FireButton({
    required super.center,
    required super.radius,
    required super.onChanged,
    required this.weapon,
  });

  final (String, String?, bool)? Function() weapon;
  final _label = HudText();

  bool get pressed => _pressed;

  @override
  void render(Canvas canvas) {
    _drawPad(canvas, HudColors.fire, flatTop: false);
    final c = Offset(radius, radius - radius * 0.1);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.7 + 0.3 * _heat)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = radius * 0.4;
    canvas.drawCircle(c, r * 0.6, line);
    canvas.drawCircle(c, 1.8, Paint()..color = HudColors.fire);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * (r * 0.35), c + d * r, line);
    }
    final tp = _label.layout(
      TextSpan(
        text: weapon()?.$1 ?? 'FIRE',
        style: hudFont(
          8.5,
          Colors.white.withValues(alpha: 0.6 + 0.35 * _heat),
          spacing: 1.2,
        ),
      ),
    );
    tp.paint(canvas, Offset(radius - tp.width / 2, c.dy + r + 2));
  }
}

/// Shows the loaded weapon's ammo; tap cycles weapons (hidden for the plain
/// cannon with nothing else on board).
class _WeaponChip extends PositionComponent with TapCallbacks {
  _WeaponChip({
    required super.position,
    required super.size,
    required this.weapon,
    required this.onTap,
  });

  final (String, String?, bool)? Function() weapon;
  final void Function() onTap;
  final _text = HudText();

  bool get _visible {
    final w = weapon();
    return w != null && (w.$2 != null || w.$3);
  }

  @override
  bool containsLocalPoint(Vector2 point) => _visible && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    final w = weapon();
    if (w != null && w.$3) onTap();
  }

  @override
  void render(Canvas canvas) {
    final w = weapon();
    if (w == null || !_visible) return;
    final plate = chamferRect(size.toRect(), 9);
    drawGlow(canvas, plate, HudColors.gold, 0.35);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, HudColors.gold.withValues(alpha: 0.85), 1.4);
    final label = '${w.$2 ?? ''}${w.$3 ? '  ⟳' : ''}'.trim();
    final tp = _text.layout(
      TextSpan(
        text: label,
        style: hudFont(12, Colors.white, spacing: 1),
      ),
    );
    tp.paint(canvas, Offset((size.x - tp.width) / 2, (size.y - tp.height) / 2));
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

  final _fuelLabel = HudText();
  final _lowLabel = HudText();

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
            : const Color(0xFFFF6B35);
    // Low fuel: the fill blinks so it's noticed in peripheral vision.
    final low = fuelFraction > 0 && fuelFraction < lowFuel;
    final blink = low ? 0.35 + 0.65 * (math.sin(_t * 9) * 0.5 + 0.5) : 1.0;

    // Cockpit plate.
    final plate = chamferRect(
      const Rect.fromLTWH(_left, _top, _barW, _barH),
      9,
    );
    drawGlow(canvas, plate, low ? const Color(0xFFFF6B35) : HudColors.cyan,
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

    if (low) {
      final tp = _lowLabel.layout(
        TextSpan(
          text: 'LOW FUEL',
          style: hudFont(
            11,
            const Color(0xFFFF6B35).withValues(alpha: blink),
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
      drawGlow(canvas, hex, const Color(0xFF4ADE80), 0.8);
      canvas.drawPath(hex, Paint()..color = const Color(0xFF4ADE80));
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

  final _lineText = HudText();
  final _labelText = HudText();

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
        i < stars ? _gold : const Color(0x55FFFFFF),
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
