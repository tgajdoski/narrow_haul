part of 'hud_touch_controls.dart';

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
          Colors.white.withValues(alpha: quantizeAlpha(0.55 + 0.4 * _heat)),
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
          Colors.white.withValues(alpha: quantizeAlpha(0.7 + 0.3 * _heat)),
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
    final plate = chamferPath(Rect.fromCenter(center: c, width: 28, height: 17), 5);
    drawGlow(canvas, plate, HudColors.gold, 0.6);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, HudColors.gold, 1.3);
    final gold = Paint()
      ..color = HudColors.gold
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(-9, 0), c + const Offset(-4, 0), gold);
    canvas.drawPath(starPath(c + const Offset(4, 0.5), 6, inner: 0.45), gold);
  }
}
