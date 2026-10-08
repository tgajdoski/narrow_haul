import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Axis-aligned static wall from [wallCenter] (meters) and half-extents.
class WallBox extends BodyComponent {
  WallBox({
    required this.wallCenter,
    required this.halfWidth,
    required this.halfHeight,
    this.theme = tutorialTheme,
    this.assets = ThemeAssets.empty,
  }) : super(paint: _fillPaint(theme, assets, wallCenter));

  /// Theme fill; with a rock texture, the shader is anchored to the world
  /// origin (not the box) so adjacent walls tile seamlessly.
  static Paint _fillPaint(ThemeSpec theme, ThemeAssets assets, Vector2 center) {
    final paint = Paint()..color = theme.rockFill;
    final img = assets.rock;
    if (img == null) return paint;
    final s = theme.rockTextureMeters / img.width;
    final m = Matrix4.translationValues(-center.x, -center.y, 0)
      ..scaleByDouble(s, s, 1, 1);
    return paint
      ..shader = ui.ImageShader(
        img,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        m.storage,
      )
      ..filterQuality = FilterQuality.medium;
  }

  final ThemeSpec theme;
  final ThemeAssets assets;

  final Vector2 wallCenter;
  final double halfWidth;
  final double halfHeight;

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = wallCenter
      ..type = BodyType.static;
    final body = world.createBody(def);
    body.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(halfWidth, halfHeight),
        friction: 0.35,
        userData: const RockTag(),
        filter: filterWall(),
      ),
    );
    return body;
  }

  @override
  void render(Canvas canvas) {
    final w = halfWidth * 2;
    final h = halfHeight * 2;

    // Base fill with slight gradient feel
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);

    canvas.drawRect(rect, paint);
    if (assets.rock != null) return;

    // Rock detail lines (pseudo texture using seeded noise)
    final seedX = wallCenter.x.round();
    final seedY = wallCenter.y.round();
    final linePaint = Paint()
      ..color = const Color(0x1A87B5E0)
      ..strokeWidth = 0.015
      ..style = PaintingStyle.stroke;

    final rng = math.Random(seedX * 31 + seedY * 17);
    for (int i = 0; i < 4; i++) {
      final x1 = -halfWidth + rng.nextDouble() * w;
      final y1 = -halfHeight + rng.nextDouble() * h;
      final x2 = x1 + (rng.nextDouble() - 0.5) * w * 0.4;
      final y2 = y1 + (rng.nextDouble() - 0.5) * h * 0.4;
      canvas.drawLine(Offset(x1, y1), Offset(x2.clamp(-halfWidth, halfWidth), y2.clamp(-halfHeight, halfHeight)), linePaint);
    }

    // Top-left highlight edge
    final edgePaint = Paint()
      ..color = const Color(0x22537EC0)
      ..strokeWidth = 0.025
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(-halfWidth, -halfHeight), Offset(halfWidth, -halfHeight), edgePaint);
    canvas.drawLine(Offset(-halfWidth, -halfHeight), Offset(-halfWidth, halfHeight), edgePaint);

    // Bottom-right shadow edge
    final shadowPaint = Paint()
      ..color = const Color(0x440B1929)
      ..strokeWidth = 0.025
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(halfWidth, -halfHeight), Offset(halfWidth, halfHeight), shadowPaint);
    canvas.drawLine(Offset(-halfWidth, halfHeight), Offset(halfWidth, halfHeight), shadowPaint);
  }
}
