import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Visual-only start helipad (no physics).
class HelipadVisual extends RectangleComponent {
  HelipadVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
  }) : super(
         position: center - sizeMeters / 2,
         size: sizeMeters,
         paint: Paint()..color = const Color(0xFF415A77).withValues(alpha: 0.5),
         priority: -1500,
       );

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Outer border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(0.1),
      ),
      Paint()
        ..color = const Color(0xFF94D2BD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06,
    );

    // "H" mark
    final midX = size.x / 2;
    final midY = size.y / 2;
    final hPaint = Paint()
      ..color = const Color(0xCCE0FBFC)
      ..strokeWidth = 0.06
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Left vertical
    canvas.drawLine(Offset(midX - 0.3, midY - 0.25), Offset(midX - 0.3, midY + 0.25), hPaint);
    // Right vertical
    canvas.drawLine(Offset(midX + 0.3, midY - 0.25), Offset(midX + 0.3, midY + 0.25), hPaint);
    // Crossbar
    canvas.drawLine(Offset(midX - 0.3, midY), Offset(midX + 0.3, midY), hPaint);

    // Corner dots
    final dotPaint = Paint()..color = const Color(0x6694D2BD);
    for (final dx in [-1.0, 1.0]) {
      for (final dy in [-1.0, 1.0]) {
        canvas.drawCircle(
          Offset(
            size.x / 2 + dx * (size.x / 2 - 0.12),
            size.y / 2 + dy * (size.y / 2 - 0.12),
          ),
          0.07,
          dotPaint,
        );
      }
    }
  }
}

/// Visual-only destination landing pad with animated chevrons.
class LandingStripVisual extends RectangleComponent {
  LandingStripVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
  }) : super(
         position: center - sizeMeters / 2,
         size: sizeMeters,
         paint: Paint()..color = const Color(0xFF1A4731).withValues(alpha: 0.55),
         priority: -1500,
       );

  double _time = 0;
  Sprite? _landingSprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _landingSprite = await Sprite.load('landing.png');
    } catch (_) {}
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    if (_landingSprite != null) {
      // Replace the solid background paint with the sprite texture.
      _landingSprite!.render(canvas, position: Vector2.zero(), size: size);
    } else {
      super.render(canvas); // solid dark-green fill fallback
    }

    // Pulsing fill overlay
    final pulse = (math.sin(_time * 2.5) * 0.5 + 0.5) * 0.12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(0.1),
      ),
      Paint()..color = Color.fromARGB((30 + (pulse * 80).round()), 74, 222, 128),
    );

    // Outer border (pulsing brightness)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(0.1),
      ),
      Paint()
        ..color = Color.fromARGB((180 + (pulse * 75).round()).clamp(0, 255), 74, 222, 128)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.07,
    );

    // Chevron stripes
    final chevronPaint = Paint()
      ..color = const Color(0x334ADE80)
      ..style = PaintingStyle.fill;
    final stripeCount = (size.x / 0.7).floor().clamp(2, 10);
    for (int i = 0; i < stripeCount; i++) {
      final x = (i + 0.5) * (size.x / stripeCount);
      final path = Path();
      final half = 0.18;
      final depth = 0.14;
      path.moveTo(x - half, size.y * 0.2);
      path.lineTo(x + half, size.y * 0.2);
      path.lineTo(x + half - depth, size.y * 0.5);
      path.lineTo(x + half, size.y * 0.8);
      path.lineTo(x - half, size.y * 0.8);
      path.lineTo(x - half + depth, size.y * 0.5);
      path.close();
      canvas.drawPath(path, chevronPaint);
    }

    // Corner landing lights (blinking)
    final lightOn = math.sin(_time * 4) > 0;
    final lightPaint = Paint()
      ..color = lightOn
          ? const Color(0xFF4ADE80)
          : const Color(0x224ADE80);
    for (final dx in [0.12, size.x - 0.12]) {
      for (final dy in [0.12, size.y - 0.12]) {
        canvas.drawCircle(Offset(dx, dy), 0.07, lightPaint);
      }
    }
  }
}
