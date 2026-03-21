import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';

/// On-screen controls for landscape: left = rotate, right = thrust.
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onThrust,
  }) : super(priority: 5000);

  final void Function(bool pressed) onRotateLeft;
  final void Function(bool pressed) onRotateRight;
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
      HoldableButton(
        position: Vector2(20, bottom),
        size: Vector2.all(btn),
        label: '⟲',
        onChanged: onRotateLeft,
      ),
    );
    add(
      HoldableButton(
        position: Vector2(20 + btn + gap, bottom),
        size: Vector2.all(btn),
        label: '⟳',
        onChanged: onRotateRight,
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
    canvas.drawRRect(r, Paint()..color = const Color(0xCC1B263B));
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFF00B4D8)
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
