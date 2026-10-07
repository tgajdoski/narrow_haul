import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';

/// Animated engine plume in the ship's local space (rear along +Y).
///
/// Uses exhaust.png (256×128, 4 frames of 64×128 each) when available,
/// otherwise falls back to procedural canvas rendering.
///
/// The sprite's flame tips point upward (bright core at bottom).
/// A Y-flip is applied so the core sits at the engine bell and the
/// tips extend away from the ship.
class ThrustPlume extends Component {
  ThrustPlume({required this.isThrusting, required this.flameStartY});

  final bool Function() isThrusting;

  /// Local Y of the engine bell on the parent ship (meters).
  final double flameStartY;
  final math.Random _rng = math.Random();
  double _time = 0;

  // Sprite animation state
  ui.Image? _exhaustImage;
  static const int _frameCount = 4;
  static const double _frameW = 64.0;
  static const double _frameH = 128.0;
  static const double _stepTime = 0.08; // ~12 fps

  // Flame dimensions in world-space meters
  static const double _flameHeight = 0.44;
  static const double _flameHalfWidth = 0.12;

  static const _coreColor = Color(0xFFFFEFCC);
  static const _midColor = Color(0xFFFFAA00);
  static const _outerColor = Color(0xFFFF4400);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _exhaustImage = await Flame.images.load('exhaust.png');
    } catch (_) {
      // Silently fall back to procedural rendering.
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    if (!isThrusting()) return;

    if (_exhaustImage != null) {
      _renderSprite(canvas);
    } else {
      _renderProcedural(canvas);
    }
  }

  void _renderSprite(Canvas canvas) {
    final frame = (_time / _stepTime).floor() % _frameCount;
    final srcRect = Rect.fromLTWH(frame * _frameW, 0, _frameW, _frameH);
    final dstRect = Rect.fromLTWH(
      -_flameHalfWidth,
      0,
      _flameHalfWidth * 2,
      _flameHeight,
    );
    
    final plumeId = CosmeticsService.getEquippedId(CosmeticsService.catPlume);
    final paint = Paint();
    if (plumeId == 'plume_green') {
      paint.colorFilter = const ColorFilter.mode(Color(0xFF00FF00), BlendMode.hue);
    } else if (plumeId == 'plume_red') {
      paint.colorFilter = const ColorFilter.mode(Color(0xFFFF0000), BlendMode.hue);
    } else if (plumeId == 'plume_rainbow') {
      final hue = (_time * 200) % 360;
      paint.colorFilter = ColorFilter.mode(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(), BlendMode.hue);
    } else if (plumeId == 'plume_cryo') {
      paint.colorFilter = const ColorFilter.mode(Color(0xFF00E5FF), BlendMode.hue);
    } else if (plumeId == 'plume_plasma') {
      paint.colorFilter = const ColorFilter.mode(Color(0xFFD500F9), BlendMode.hue);
    } else if (plumeId == 'plume_afterburner') {
      paint.colorFilter = const ColorFilter.mode(Color(0xFFFF8C00), BlendMode.hue);
    } else if (plumeId == 'plume_aurora') {
      final hue = 150 + 70 * math.sin(_time * 3);
      paint.colorFilter = ColorFilter.mode(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor(), BlendMode.hue);
    }

    // The source sprite has the core at the bottom and tips pointing upward.
    // Flip vertically so the core appears at the engine bell (flameStartY)
    // and the tips extend downward (increasing Y = away from ship).
    canvas.save();
    canvas.translate(0, flameStartY + _flameHeight);
    canvas.scale(1.0, -1.0);
    canvas.drawImageRect(_exhaustImage!, srcRect, dstRect, paint);
    canvas.restore();
  }

  void _renderProcedural(Canvas canvas) {
    final base = flameStartY;
    final flicker = 0.85 + math.sin(_time * 28) * 0.15;
    
    final plumeId = CosmeticsService.getEquippedId(CosmeticsService.catPlume);
    Color coreC = _coreColor;
    Color midC = _midColor;
    Color outerC = _outerColor;
    
    if (plumeId == 'plume_green') {
      coreC = const Color(0xFFCCFFCC);
      midC = const Color(0xFF00AA00);
      outerC = const Color(0xFF004400);
    } else if (plumeId == 'plume_red') {
      coreC = const Color(0xFFFFCCCC);
      midC = const Color(0xFFAA0000);
      outerC = const Color(0xFF440000);
    } else if (plumeId == 'plume_rainbow') {
      final hue = (_time * 200) % 360;
      coreC = HSVColor.fromAHSV(1.0, hue, 0.2, 1.0).toColor();
      midC = HSVColor.fromAHSV(1.0, hue, 0.8, 1.0).toColor();
      outerC = HSVColor.fromAHSV(1.0, hue, 1.0, 0.8).toColor();
    } else if (plumeId == 'plume_cryo') {
      coreC = const Color(0xFFE0FFFF);
      midC = const Color(0xFF00B8D4);
      outerC = const Color(0xFF004D60);
    } else if (plumeId == 'plume_plasma') {
      coreC = const Color(0xFFF8E1FF);
      midC = const Color(0xFFD500F9);
      outerC = const Color(0xFF4A148C);
    } else if (plumeId == 'plume_afterburner') {
      coreC = const Color(0xFFE0F2FF);
      midC = const Color(0xFFFF9F1C);
      outerC = const Color(0xFF7B2CBF);
    } else if (plumeId == 'plume_aurora') {
      final hue = 150 + 70 * math.sin(_time * 3);
      coreC = HSVColor.fromAHSV(1.0, hue, 0.2, 1.0).toColor();
      midC = HSVColor.fromAHSV(1.0, hue, 0.8, 1.0).toColor();
      outerC = HSVColor.fromAHSV(1.0, (hue + 60) % 360, 1.0, 0.8).toColor();
    }

    // Outer glow bloom
    canvas.drawCircle(
      Offset(0, base + 0.05),
      0.22 * flicker,
      Paint()
        ..color = outerC.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12),
    );

    // Flame cone (3 layers)
    final lengths = [0.40 * flicker, 0.28 * flicker, 0.18 * flicker];
    final widths = [0.12, 0.09, 0.06];
    final colors = [outerC, midC, coreC];
    final opacities = [180, 220, 255];

    for (int layer = 0; layer < 3; layer++) {
      final path = Path();
      final halfW = widths[layer] * (0.9 + math.sin(_time * 18 + layer) * 0.1);
      final len = lengths[layer];
      path.moveTo(-halfW, base);
      path.cubicTo(
        -halfW * 0.6, base + len * 0.4,
        -halfW * 0.3, base + len * 0.7,
        0, base + len,
      );
      path.cubicTo(
        halfW * 0.3, base + len * 0.7,
        halfW * 0.6, base + len * 0.4,
        halfW, base,
      );
      path.close();

      final color = colors[layer];
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromARGB(
            opacities[layer],
            (color.r * 255).round(),
            (color.g * 255).round(),
            (color.b * 255).round(),
          )
          ..style = PaintingStyle.fill,
      );
    }

    // Particle sparks
    for (var i = 0; i < 5; i++) {
      final t = _rng.nextDouble();
      final ox = (_rng.nextDouble() - 0.5) * 0.1 * (1 + t);
      final oy = base + 0.05 + t * 0.35 * flicker;
      final r = 0.02 + (1 - t) * 0.03;
      canvas.drawCircle(
        Offset(ox, oy),
        r,
        Paint()..color = Color.lerp(coreC, outerC, t)!.withValues(alpha: (1 - t) * 0.9),
      );
    }
  }
}
