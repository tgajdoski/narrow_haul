import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Visual-only start helipad (no physics).
class HelipadVisual extends RectangleComponent {
  HelipadVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
    Color base = const Color(0xFF415A77),
    this.accent = const Color(0xFF94D2BD),
  }) : super(
         position: center - sizeMeters / 2,
         size: sizeMeters,
         paint: Paint()..color = base.withValues(alpha: 0.5),
         priority: -1500,
       );

  final Color accent;

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
        ..color = accent
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
    final dotPaint = Paint()..color = accent.withValues(alpha: 0.4);
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
///
/// Tutorial goals are hover zones: the whole box is the pad. Cave pads
/// ([floorDrop] set) have a rock floor [floorDrop] below the box, where ship
/// and pod actually rest: the deck is drawn on that floor and the box above
/// it is only a faint approach beacon.
class LandingStripVisual extends RectangleComponent {
  LandingStripVisual({
    required Vector2 center,
    required Vector2 sizeMeters,
    this.floorDrop,
  }) : super(
         position: center - sizeMeters / 2,
         size: sizeMeters,
         paint: Paint()..color = const Color(0xFF1A4731).withValues(alpha: 0.55),
         // Above the rock (−1700), below ship and pod.
         priority: -1500,
       );

  /// Distance from the box's bottom down to the landing floor (m).
  final double? floorDrop;

  /// Deck plate thickness, drawn into the rock under the floor line (m).
  static const double deckDepth = 0.26;

  static const Color _green = Color(0xFF4ADE80);

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
    final drop = floorDrop;
    if (drop != null) {
      _renderCavePad(canvas, size.y + drop);
      return;
    }
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

  void _renderCavePad(Canvas canvas, double floorY) {
    final pulse = math.sin(_time * 2.5) * 0.5 + 0.5;
    final w = size.x;

    // Approach beacon: a light column fading up from the deck.
    final column = Rect.fromLTWH(0, 0, w, floorY);
    canvas.drawRect(
      column,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _green.withValues(alpha: 0.10 + 0.08 * pulse),
            _green.withValues(alpha: 0.0),
          ],
        ).createShader(column),
    );
    final edge = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [_green.withValues(alpha: 0.55), _green.withValues(alpha: 0.0)],
      ).createShader(column)
      ..strokeWidth = 0.04;
    canvas.drawLine(Offset(0, floorY), const Offset(0, 0), edge);
    canvas.drawLine(Offset(w, floorY), Offset(w, 0), edge);

    // Deck plate set into the floor; its top edge is the landing surface.
    final deck = Rect.fromLTWH(0, floorY, w, deckDepth);
    canvas.drawRect(deck, Paint()..color = const Color(0xFF1B2433));
    final stripeCount = (w / 0.7).floor().clamp(2, 10);
    final chevron = Paint()..color = _green.withValues(alpha: 0.35 + 0.25 * pulse);
    for (int i = 0; i < stripeCount; i++) {
      final x = (i + 0.5) * (w / stripeCount);
      // Chevrons point at the pad's centre.
      final dir = x < w / 2 ? 1.0 : -1.0;
      final top = floorY + deckDepth * 0.25;
      final mid = floorY + deckDepth * 0.5;
      final bot = floorY + deckDepth * 0.75;
      final path = Path()
        ..moveTo(x - 0.1 * dir, top)
        ..lineTo(x + 0.02 * dir, top)
        ..lineTo(x + 0.12 * dir, mid)
        ..lineTo(x + 0.02 * dir, bot)
        ..lineTo(x - 0.1 * dir, bot)
        ..lineTo(x, mid)
        ..close();
      canvas.drawPath(path, chevron);
    }
    canvas.drawLine(
      Offset(0, floorY),
      Offset(w, floorY),
      Paint()
        ..color = _green.withValues(alpha: 0.75 + 0.25 * pulse)
        ..strokeWidth = 0.05,
    );

    // Edge lights on the deck corners (blinking).
    final lightOn = math.sin(_time * 4) > 0;
    final light = Paint()..color = lightOn ? _green : _green.withValues(alpha: 0.15);
    canvas.drawCircle(Offset(0.1, floorY - 0.05), 0.06, light);
    canvas.drawCircle(Offset(w - 0.1, floorY - 0.05), 0.06, light);
  }
}
