import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';

/// On-screen controls for landscape: left = rotate, right = thrust.
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateAxis,
    required this.onThrust,
  }) : super(priority: 5000);

  final void Function(double axis) onRotateAxis;
  final void Function(bool pressed) onThrust;

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
    _layout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (children.isEmpty && size.x > 0 && size.y > 0) {
      _layout();
    }
  }

  void _layout() {
    if (size.x <= 0 || size.y <= 0) return;
    for (final c in children.toList()) {
      c.removeFromParent();
    }

    const btn = 72.0;
    const gap = 12.0;
    final bottom = size.y - 24 - btn;

    add(
      RotatePad(
        position: Vector2(20, bottom),
        size: Vector2(btn * 2 + gap, btn),
        onAxisChanged: onRotateAxis,
      ),
    );

    const thrustW = 100.0;
    add(
      HoldableButton(
        position: Vector2(size.x - thrustW - 24, bottom),
        size: Vector2(thrustW, btn),
        label: 'THRUST',
        onChanged: onThrust,
      ),
    );
  }
}

class RotatePad extends PositionComponent with DragCallbacks, TapCallbacks {
  RotatePad({
    required super.position,
    required super.size,
    required this.onAxisChanged,
  }) : super(anchor: Anchor.topLeft);

  final void Function(double axis) onAxisChanged;

  static const _deadzone = 0.08;
  double _axis = 0;

  void _emitAxis(double next) {
    final clamped = next.clamp(-1.0, 1.0);
    final withDeadzone = clamped.abs() < _deadzone ? 0.0 : clamped;
    if ((withDeadzone - _axis).abs() < 0.0001) return;
    _axis = withDeadzone;
    onAxisChanged(_axis);
  }

  double _axisFromLocalX(double x) {
    final t = (x / size.x).clamp(0.0, 1.0);
    return t * 2 - 1;
  }

  @override
  void render(Canvas canvas) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(12),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0x551B263B));
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xCC00B4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final center = size / 2;
    canvas.drawLine(
      Offset(center.x, 8),
      Offset(center.x, size.y - 8),
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 2,
    );

    final knobX = center.x + _axis * (size.x * 0.35);
    canvas.drawCircle(
      Offset(knobX, center.y),
      size.y * 0.27,
      Paint()..color = const Color(0xDD00B4D8),
    );
    super.render(canvas);
  }

  @override
  void onTapDown(TapDownEvent event) => _emitAxis(_axisFromLocalX(event.localPosition.x));

  @override
  void onTapUp(TapUpEvent event) => _emitAxis(0);

  @override
  void onTapCancel(TapCancelEvent event) => _emitAxis(0);

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _emitAxis(_axisFromLocalX(event.localPosition.x));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    _emitAxis(_axisFromLocalX(event.localEndPosition.x));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _emitAxis(0);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _emitAxis(0);
  }
}

class HoldableButton extends PositionComponent with TapCallbacks {
  HoldableButton({
    required super.position,
    required super.size,
    required this.label,
    required this.onChanged,
  }) : super(anchor: Anchor.topLeft);

  final String label;
  final void Function(bool pressed) onChanged;

  late TextComponent _label;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _label = TextComponent(
      text: label,
      anchor: Anchor.center,
      position: size / 2,
      textRenderer: TextPaint(
        style: TextStyle(
          color: Colors.white,
          fontSize: label == 'THRUST' ? 15 : 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    await add(_label);
  }

  @override
  void render(Canvas canvas) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(10),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0x551B263B));
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xCC00B4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    super.render(canvas);
  }

  @override
  void onTapDown(TapDownEvent event) => onChanged(true);

  @override
  void onTapUp(TapUpEvent event) => onChanged(false);

  @override
  void onTapCancel(TapCancelEvent event) => onChanged(false);
}
