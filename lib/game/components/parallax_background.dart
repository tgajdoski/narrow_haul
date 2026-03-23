// ui.Image is from dart:ui; Canvas/Paint/Rect/Color come from Flutter.
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

/// Three-layer parallax background that scrolls with the camera.
///
/// Layers move at progressively higher fractions of the camera speed:
///   far  (0.04 × cam) → almost static, very distant
///   mid  (0.15 × cam) → gentle drift
///   near (0.38 × cam) → noticeable depth
///
/// Added directly to the game (not the viewport) at priority −9999 so it
/// renders before the CameraComponent and therefore behind the game world,
/// tile layers, and all HUD elements.
class ParallaxBackground extends PositionComponent with HasGameReference<Forge2DGame> {
  ParallaxBackground() : super(priority: -9999);

  static const _files = ['far.png', 'mid.png', 'near.png'];

  // Fraction of camera displacement applied to each layer.
  static const _speedX = [0.04, 0.15, 0.38];
  static const _speedY = [0.02, 0.07, 0.18];

  // Opacity tint per layer — far layers are dimmer to simulate depth haze.
  static const _alphas = [0.50, 0.72, 0.92];

  final List<ui.Image?> _images = [null, null, null]; // ui.Image from dart:ui

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Set size eagerly so PositionComponent doesn't clip to a zero-rect
    // on the first render frame (onGameResize fires after the first tick).
    size = game.size;
    for (int i = 0; i < _files.length; i++) {
      try {
        _images[i] = await Flame.images.load(_files[i]);
      } catch (_) {}
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void render(Canvas canvas) {
    if (size.x <= 0 || size.y <= 0) return;

    // Camera world position drives the parallax offset for each layer.
    final camPos = game.camera.viewfinder.position;
    final zoom = game.camera.viewfinder.zoom;

    for (int i = 0; i < _images.length; i++) {
      final img = _images[i];
      if (img == null) continue;
      _drawLayer(canvas, img, camPos, zoom, _speedX[i], _speedY[i], _alphas[i]);
    }
  }

  void _drawLayer(
    Canvas canvas,
    ui.Image img,
    Vector2 camPos,
    double zoom,
    double sx,
    double sy,
    double alpha,
  ) {
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();

    // Scale image so its height exactly fills the viewport height.
    final scale = size.y / ih;
    final scaledW = iw * scale;
    final scaledH = size.y;

    // Pixel offset for this layer. As the camera moves right/down the
    // background shifts left/up by a fraction — giving the parallax feel.
    final rawShiftX = camPos.x * zoom * sx;
    final rawShiftY = camPos.y * zoom * sy;

    // Wrap to [0, scaled dimension) so tiling is seamless.
    final shiftX = rawShiftX % scaledW;
    final shiftY = rawShiftY % scaledH;

    // 1 px overlap between tiles eliminates the hairline seam that can appear
    // due to sub-pixel rounding when tiles are placed next to each other.
    const seam = 1.0;

    final paint = Paint()
      ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255)
      ..filterQuality = FilterQuality.low;
    final srcRect = ui.Rect.fromLTWH(0, 0, iw, ih);

    // Tile to cover the entire viewport.  Starting one tile early handles
    // the negative wrap correctly in all scroll directions.
    double startX = -shiftX;
    if (startX > 0) startX -= scaledW;

    double startY = -shiftY;
    if (startY > 0) startY -= scaledH;

    for (double x = startX; x < size.x; x += scaledW) {
      for (double y = startY; y < size.y; y += scaledH) {
        canvas.drawImageRect(
          img,
          srcRect,
          ui.Rect.fromLTWH(x, y, scaledW + seam, scaledH + seam),
          paint,
        );
      }
    }
  }
}
