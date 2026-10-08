import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// On-screen controls for landscape play.
///
/// Left 50% of screen → [_FloatingJoystick]: appears where the thumb lands.
/// Horizontal axis [-1..1] drives rotation.
///
/// Right side → [_ThrustButton]: large circular hold-button for engine thrust.
/// A ship with something to fire adds [_FireButton] above it (tap = one
/// shot, hold = auto-fire) and the [_WeaponRail] beside both.
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateAxis,
    this.onStick,
    required this.onThrust,
    this.onFire,
    this.onSelectWeapon,
  }) : super(priority: 5000);

  final void Function(double axis) onRotateAxis;

  /// The stick as a direction (x, y in −1…1, screen axes) for point-to-steer.
  final void Function(double x, double y)? onStick;
  final void Function(bool pressed) onThrust;
  final void Function(bool pressed)? onFire;

  /// Tap on an ammo rail slot: pick that weapon.
  final void Function(String id)? onSelectWeapon;

  /// What's on board and which one FIRE fires; null = nothing to fire.
  WeaponHud? get weapon => _weapon;
  WeaponHud? _weapon;
  set weapon(WeaponHud? v) {
    final before = _weapon?.selected.id;
    final after = v?.selected.id;
    // A switch (rail, key, crate) names the new weapon; a level's first
    // sync doesn't.
    if (v == null) {
      _toastLeft = 0;
    } else if (before != null && after != before) {
      _toastLeft = toastSeconds;
    }
    _weapon = v;
  }

  /// How long the full name of a newly picked weapon shows on the rail.
  static const double toastSeconds = 1.2;
  double _toastLeft = 0;

  /// 0–1 opacity of that name (fades over the last 0.3 s).
  double get toastAlpha => (_toastLeft / 0.3).clamp(0.0, 1.0);

  @override
  void update(double dt) {
    super.update(dt);
    if (_toastLeft > 0) _toastLeft = math.max(0, _toastLeft - dt);
  }

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
  _WeaponRail? _rail;

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
    _rail?.removeFromParent();
    _rail = null;

    _joystick = _FloatingJoystick(
      areaSize: Vector2(sz.x * 0.5, sz.y),
      position: Vector2(_leftHanded ? sz.x * 0.5 : 0, 0),
      onAxisChanged: onRotateAxis,
      onStick: onStick,
      hintFraction: _leftHanded ? 0.78 : 0.22,
      // The joystick covers one half: only that half's outer edge is inset.
      hintInsets: _leftHanded
          ? EdgeInsets.only(right: _insets.right, bottom: _insets.bottom)
          : EdgeInsets.only(left: _insets.left, bottom: _insets.bottom),
    );

    final layout = HudButtonLayout(
      Size(sz.x, sz.y),
      insets: _insets,
      leftHanded: _leftHanded,
    );
    _thrustBtn = _ThrustButton(
      center: Vector2(layout.thrust.dx, layout.thrust.dy),
      radius: HudButtonLayout.thrustRadius,
      onChanged: onThrust,
    );

    add(_joystick!);
    add(_thrustBtn!);

    if (_showFire && onFire != null) {
      _fireBtn = _FireButton(
        center: Vector2(layout.fire.dx, layout.fire.dy),
        radius: HudButtonLayout.fireRadius,
        onChanged: onFire!,
        weapon: () => weapon,
        innerSide: layout.innerSide,
      );
      add(_fireBtn!);
      _rail = _WeaponRail(
        layout: layout,
        weapon: () => weapon,
        toastAlpha: () => toastAlpha,
        onSelect: (id) => onSelectWeapon?.call(id),
      )..size = sz;
      add(_rail!);
    }
  }
}

/// One weapon on board, as the FIRE pad and the ammo rail show it.
class WeaponSlot {
  const WeaponSlot({
    required this.id,
    required this.kind,
    required this.label,
    required this.name,
    this.count,
    this.ammo = 0,
    this.peak = 0,
    this.costsStar = false,
  });

  final String id;
  final WeaponKind kind;

  /// Short label under the FIRE icon ('BOMB'), and the full name the rail
  /// shows for a moment after a switch ('Gravity Bomb').
  final String label;
  final String name;

  /// '×3' / '8s'; null for the cannon (it costs fuel, not ammo).
  final String? count;

  /// Units left and the most held this flight: the FIRE pad's ammo ring.
  final double ammo;
  final double peak;

  /// The next shot would spend the player's own stock and cap the run at 2★.
  final bool costsStar;

  bool get continuous => kind == WeaponKind.laser;
}

/// Everything the weapon HUD shows: the slots in rail order and the one
/// FIRE fires.
class WeaponHud {
  const WeaponHud({required this.slots, required this.selectedIndex});

  final List<WeaponSlot> slots;
  final int selectedIndex;

  WeaponSlot get selected => slots[selectedIndex];

  /// The rail shows only when there's a choice; a lone weapon's icon and
  /// ammo are on the FIRE pad already.
  bool get showRail => slots.length > 1;
}

/// Where THRUST, FIRE and the ammo rail sit, in screen pixels. Pure
/// geometry, shared by the HUD and its layout test.
class HudButtonLayout {
  HudButtonLayout(this.screen, {this.insets = EdgeInsets.zero, this.leftHanded = false}) {
    final x = leftHanded
        ? insets.left + margin + thrustRadius
        : screen.width - insets.right - margin - thrustRadius;
    final y = screen.height - insets.bottom - margin - thrustRadius;
    thrust = Offset(x, y);
    // Directly above thrust: the same thumb rocks between the two.
    fire = Offset(x, y - thrustRadius - 18 - fireRadius);
  }

  static const double thrustRadius = 52;
  static const double fireRadius = 40;
  static const double margin = 28;

  /// Rail slot hexagon radius and centre-to-centre spacing.
  static const double slotRadius = 15;
  static const double slotSpacing = 35;

  /// The top-right minimap (12 px margin, at most 90 px tall) and the
  /// top-left fuel gauge end above this line; the rail stays below it.
  static const double topClear = 106;

  final Size screen;
  final EdgeInsets insets;
  final bool leftHanded;
  late final Offset thrust;
  late final Offset fire;

  /// Toward the screen centre: −1 for a right-hand layout.
  double get innerSide => leftHanded ? 1 : -1;

  /// Centres of [n] rail slots, top to bottom: a column on the screen-centre
  /// side of THRUST/FIRE, centred on FIRE where it fits, squeezed (never
  /// tighter than the slots) when it doesn't.
  List<Offset> railCenters(int n) {
    if (n <= 0) return const [];
    final x = thrust.dx + innerSide * (thrustRadius + 14 + slotRadius);
    final minY = insets.top + topClear + slotRadius;
    final maxY = screen.height - insets.bottom - 6 - slotRadius;
    final room = math.max(0.0, maxY - minY);
    final step = n == 1
        ? 0.0
        : math.max(slotRadius * 2, math.min(slotSpacing, room / (n - 1)));
    final span = step * (n - 1);
    final top = (fire.dy - span / 2).clamp(minY, math.max(minY, maxY - span));
    return [for (var i = 0; i < n; i++) Offset(x, top + i * step)];
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
    this.onStick,
    this.hintFraction = 0.22,
    this.hintInsets = EdgeInsets.zero,
  }) : super(
          position: position,
          size: areaSize,
          anchor: Anchor.topLeft,
        );

  final void Function(double axis) onAxisChanged;
  final void Function(double x, double y)? onStick;

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

  void _emit(double raw, [double rawY = 0]) {
    final clamped = raw.clamp(-1.0, 1.0);
    _axis = clamped.abs() < _deadzone ? 0.0 : clamped;
    onAxisChanged(_axis);
    onStick?.call(clamped, rawY.clamp(-1.0, 1.0));
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

/// Weapon trigger: the thrust button's touch handling with the loaded
/// weapon's icon, its ammo ring and, when the next shot would spend the
/// player's own stock, a −★ badge.
class _FireButton extends _ThrustButton {
  _FireButton({
    required super.center,
    required super.radius,
    required super.onChanged,
    required this.weapon,
    required this.innerSide,
  });

  final WeaponHud? Function() weapon;

  /// Toward the screen centre (−1 / 1): where the −★ badge sits, clear of
  /// the minimap.
  final double innerSide;
  final _label = HudText();

  bool get pressed => _pressed;

  @override
  void render(Canvas canvas) {
    _drawPad(canvas, HudColors.fire, flatTop: false);
    final slot = weapon()?.selected;
    final c = Offset(radius, radius - radius * 0.12);
    drawWeaponGlyph(
      canvas,
      slot?.kind ?? WeaponKind.cannon,
      c,
      radius * 0.36,
      color: Colors.white.withValues(alpha: 0.75 + 0.25 * _heat),
    );
    final text = slot == null
        ? 'FIRE'
        : [slot.label, if (slot.count != null) slot.count].join(' ');
    final tp = _label.layout(
      TextSpan(
        text: text,
        style: hudFont(
          10.5,
          Colors.white.withValues(alpha: 0.7 + 0.3 * _heat),
          spacing: 1.1,
        ),
      ),
    );
    tp.paint(canvas, Offset(radius - tp.width / 2, c.dy + radius * 0.42));
    if (slot != null && slot.count != null) _drawAmmoRing(canvas, slot);
    if (slot != null && slot.costsStar) _drawStarBadge(canvas);
  }

  /// Arc over the top of the pad: one pip per unit (up to 8, lit while
  /// left), or a fuel-style bar for the laser's seconds.
  void _drawAmmoRing(Canvas canvas, WeaponSlot slot) {
    final rect = Rect.fromCircle(center: Offset(radius, radius), radius: radius + 6);
    const start = -math.pi * 5 / 6;
    const sweep = math.pi * 2 / 3;
    final peak = math.max(slot.peak, slot.ammo);
    Paint seg(bool lit) => Paint()
      ..color = lit ? HudColors.gold : Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.butt;
    if (slot.continuous) {
      canvas.drawArc(rect, start, sweep, false, seg(false));
      final f = peak <= 0 ? 0.0 : (slot.ammo / peak).clamp(0.0, 1.0);
      canvas.drawArc(rect, start, sweep * f, false, seg(true));
      return;
    }
    final total = math.min(8, peak.round());
    final lit = math.min(8, slot.ammo.round());
    if (total <= 0) return;
    const gap = 0.07;
    final each = (sweep - gap * (total - 1)) / total;
    for (var i = 0; i < total; i++) {
      canvas.drawArc(rect, start + i * (each + gap), each, false, seg(i < lit));
    }
  }

  /// '−★' plate on the pad's screen-centre flank (the star is drawn: the
  /// HUD font has no ★).
  void _drawStarBadge(Canvas canvas) {
    final c = Offset(radius + innerSide * radius * 0.95, radius * 0.72);
    final plate = chamferRect(Rect.fromCenter(center: c, width: 28, height: 17), 5);
    drawGlow(canvas, plate, HudColors.gold, 0.6);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, HudColors.gold, 1.3);
    final gold = Paint()
      ..color = HudColors.gold
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(-9, 0), c + const Offset(-4, 0), gold);
    canvas.drawPath(_starPath(c + const Offset(4, 0.5), 6), gold);
  }

  static Path _starPath(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = i.isEven ? r : r * 0.45;
      final v = c + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
    }
    return p..close();
  }
}

/// The ammo rail: a column of hex slots beside FIRE, one per weapon on
/// board, each with its icon and ammo. Tap one to load it. The loaded slot
/// is lit gold, and a weapon whose next shot spends the player's own stock
/// (2★ cap) carries a gold dot. Right after a switch the loaded slot's
/// count gives way to the weapon's full name for a moment.
class _WeaponRail extends PositionComponent with TapCallbacks {
  _WeaponRail({
    required this.layout,
    required this.weapon,
    required this.toastAlpha,
    required this.onSelect,
  });

  final HudButtonLayout layout;
  final WeaponHud? Function() weapon;
  final double Function() toastAlpha;
  final void Function(String id) onSelect;

  final _counts = List.generate(6, (_) => HudText());
  final _toast = HudText();

  List<Offset> _centers(WeaponHud w) =>
      layout.railCenters(math.min(w.slots.length, _counts.length));

  int? _slotAt(Offset p) {
    final w = weapon();
    if (w == null || !w.showRail) return null;
    final centers = _centers(w);
    for (var i = 0; i < centers.length; i++) {
      final d = p - centers[i];
      if (d.dx.abs() <= HudButtonLayout.slotRadius + 6 &&
          d.dy.abs() <= HudButtonLayout.slotSpacing / 2) {
        return i;
      }
    }
    return null;
  }

  @override
  bool containsLocalPoint(Vector2 point) => _slotAt(Offset(point.x, point.y)) != null;

  @override
  void onTapDown(TapDownEvent event) {
    final i = _slotAt(Offset(event.localPosition.x, event.localPosition.y));
    final w = weapon();
    if (i == null || w == null) return;
    onSelect(w.slots[i].id);
  }

  @override
  void render(Canvas canvas) {
    final w = weapon();
    if (w == null || !w.showRail) return;
    final centers = _centers(w);
    const r = HudButtonLayout.slotRadius;
    final side = layout.innerSide;
    final toast = toastAlpha();
    for (var i = 0; i < centers.length; i++) {
      final s = w.slots[i];
      final c = centers[i];
      final on = i == w.selectedIndex;
      final hex = hexPath(c, r);
      if (on) drawGlow(canvas, hex, HudColors.gold, 0.7);
      canvas.drawPath(hex, Paint()..color = on ? HudColors.plate : HudColors.plateDark);
      drawStroke(
        canvas,
        hex,
        on ? HudColors.gold : HudColors.cyan.withValues(alpha: 0.55),
        on ? 2 : 1.2,
      );
      drawWeaponGlyph(
        canvas,
        s.kind,
        c,
        r * 0.5,
        color: Colors.white.withValues(alpha: on ? 1 : 0.6),
      );
      if (s.costsStar) {
        canvas.drawCircle(c + Offset(-side * r * 0.7, -r * 0.62), 3, Paint()..color = HudColors.gold);
      }
      // Count on the screen-centre side; the loaded slot names its weapon
      // for a moment after a switch.
      final named = on && toast > 0;
      final tp = named
          ? _toast.layout(TextSpan(
              text: [s.name.toUpperCase(), if (s.count != null) s.count].join(' '),
              style: hudFont(11, HudColors.gold.withValues(alpha: toast), spacing: 1),
            ))
          : _counts[i].layout(TextSpan(
              text: s.count ?? '',
              style: hudFont(
                10,
                Colors.white.withValues(alpha: on ? 0.95 : 0.6),
                spacing: 0.5,
              ),
            ));
      final x = side < 0 ? c.dx - r - 5 - tp.width : c.dx + r + 5;
      tp.paint(canvas, Offset(x, c.dy - tp.height / 2));
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
