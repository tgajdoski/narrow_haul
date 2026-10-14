part of 'hud_touch_controls.dart';

class _FloatingJoystick extends PositionComponent with DragCallbacks, TapCallbacks {
  _FloatingJoystick({
    required Vector2 areaSize,
    required Vector2 position,
    required this.onAxisChanged,
    this.onStick,
    required this.restCenter,
    this.onTap,
  }) : super(
          position: position,
          size: areaSize,
          anchor: Anchor.topLeft,
        );

  final void Function(double axis) onAxisChanged;
  final void Function(double x, double y)? onStick;

  /// A tap while tilt steering (the stick is hidden): recentre the tilt.
  final void Function()? onTap;

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (FlightTuning.tilt) onTap?.call();
  }

  /// Where the idle dial rests, in this area's coordinates
  /// ([HudButtonLayout.dialRest]).
  final Offset restCenter;

  static const double _maxKnobRadius = 56.0;
  static const double _baseOuterRadius = HudButtonLayout.dialRadius;
  static const double _knobRadius = 28.0;
  static const double _deadzone = FlightTuning.stickDeadzone;

  int? _trackingPointerId;
  Vector2? _baseCenter;
  Vector2? _knobCenter;
  bool _active = false;

  /// Where the dial floats while a thumb holds it (this area's coordinates).
  Vector2? get heldCenter => _baseCenter;

  /// Last emitted axis, for lighting the side the pilot is turning to.
  double _axis = 0;

  void _emit(double raw, [double rawY = 0]) {
    final clamped = raw.clamp(-1.0, 1.0);
    _axis = clamped.abs() < _deadzone ? 0.0 : clamped;
    onAxisChanged(_axis);
    onStick?.call(clamped, rawY.clamp(-1.0, 1.0));
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    // Tilt steering: no stick on screen (a tap still recentres the tilt).
    if (_trackingPointerId != null || FlightTuning.tilt) return;
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
    _emit(dx / _maxKnobRadius, dy / _maxKnobRadius);
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
  void update(double dt) {
    super.update(dt);
    // Switched to tilt mid-drag (pause → Settings): let go of the stick.
    if (FlightTuning.tilt && _trackingPointerId != null) _reset();
  }

  @override
  void render(Canvas canvas) {
    if (FlightTuning.tilt) return;
    if (_active) {
      _drawJoystick(canvas);
    } else {
      _drawHint(canvas);
    }
  }

  /// Resting position hint: the full dial (base + centred knob) at a fixed
  /// bottom corner so the player always sees where to steer.
  void _drawHint(Canvas canvas) {
    final c = restCenter;
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
    // Two-speed modes: gold notches where the precise zone ends.
    const boostX = FlightTuning.boostStart * _maxKnobRadius;
    final notch = Paint()
      ..color = HudColors.gold.withValues(alpha: 0.55 * a)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (FlightTuning.steer.hasZones) {
      for (final side in const [-1.0, 1.0]) {
        final x = c.dx + side * boostX;
        canvas.drawLine(Offset(x, c.dy - 7), Offset(x, c.dy + 7), notch);
      }
    }
    if (FlightTuning.steer.isPointer) {
      _drawPointer(canvas, c, active: active, alpha: a);
      return;
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

  /// Point-to-steer: a needle from the centre to the knob (the heading the
  /// nose turns to) and a dashed ring where pointing starts to count.
  void _drawPointer(Canvas canvas, Offset c, {required bool active, required double alpha}) {
    final ring = Paint()
      ..color = HudColors.cyan.withValues(alpha: 0.3 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const r = FlightTuning.pointerMinStick * _maxKnobRadius;
    for (var i = 0; i < 12; i++) {
      final a0 = i * math.pi / 6;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, math.pi / 12, false, ring);
    }
    final knob = _knobCenter;
    if (!active || knob == null) return;
    final d = Offset(knob.x, knob.y) - c;
    if (d.distance < r) return;
    canvas.drawLine(
      c,
      c + d,
      Paint()
        ..color = HudColors.cyanBright.withValues(alpha: 0.85)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
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
