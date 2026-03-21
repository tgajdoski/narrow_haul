import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Visual only — start helipad (does not collide).
class HelipadVisual extends RectangleComponent {
  HelipadVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
  }) : super(
         position: center - Vector2(sizeMeters.x / 2, sizeMeters.y / 2),
         size: sizeMeters,
         paint: Paint()..color = const Color(0xFF415A77).withValues(alpha: 0.65),
         priority: -1500,
       );

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final border = Paint()
      ..color = const Color(0xFF94D2BD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(0.08),
    );
    canvas.drawRRect(r, border);
    final hPaint = Paint()
      ..color = const Color(0xFFE0E1DD)
      ..strokeWidth = 0.05
      ..style = PaintingStyle.stroke;
    final midY = size.y / 2;
    canvas.drawLine(Offset(size.x * 0.2, midY), Offset(size.x * 0.8, midY), hPaint);
    canvas.drawLine(Offset(size.x / 2, size.y * 0.25), Offset(size.x / 2, size.y * 0.75), hPaint);
  }
}

/// Visual only — destination landing strip.
class LandingStripVisual extends RectangleComponent {
  LandingStripVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
  }) : super(
         position: center - Vector2(sizeMeters.x / 2, sizeMeters.y / 2),
         size: sizeMeters,
         paint: Paint()..color = const Color(0xFF2D6A4F).withValues(alpha: 0.45),
         priority: -1500,
       );

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final border = Paint()
      ..color = const Color(0xFF4ADE80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(0.1),
      ),
      border,
    );
  }
}
