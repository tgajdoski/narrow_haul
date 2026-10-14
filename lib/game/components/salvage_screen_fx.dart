import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/post_process.dart';
import 'package:flutter/material.dart';

/// Full-screen salvage effects over the world, under the HUD: Blackout's
/// headlamp, Spore Trip's colour drift (on top of its shader, or alone
/// where shaders aren't available) and Chrono's blue vignette.
class SalvageScreenFx extends PositionComponent {
  SalvageScreenFx() : super(priority: 4700);

  /// Ship centre on screen, zoom (px per metre) and heading; set each frame.
  Offset shipScreen = Offset.zero;
  double pxPerMeter = 28;
  double noseAngle = 0;

  /// 0…1 each, eased by the effect.
  double darkness = 0;
  double hallucination = 0;
  double chrono = 0;

  double _t = 0;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final screen = Offset.zero & size.toSize();
    if (chrono > 0) {
      canvas.drawRect(
        screen,
        Paint()
          ..shader = ui.Gradient.radial(
            screen.center,
            screen.longestSide * 0.62,
            [const Color(0x00000000), const Color(0xFF2962FF).withValues(alpha: 0.32 * chrono)],
            [0.55, 1.0],
          ),
      );
    }
    if (hallucination > 0) {
      // Slow bands of shifting colour.
      for (var i = 0; i < 3; i++) {
        final hue = (_t * 40 + i * 120) % 360;
        final color = HSVColor.fromAHSV(0.12 * hallucination, hue, 0.8, 1).toColor();
        final y = screen.height * (0.5 + 0.45 * math.sin(_t * 0.7 + i * 2.1));
        canvas.drawRect(
          screen,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(
              Offset(0, y - screen.height * 0.35),
              Offset(0, y + screen.height * 0.35),
              [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
              [0, 0.5, 1],
            ),
        );
      }
    }
    if (darkness > 0) {
      canvas.saveLayer(screen, Paint());
      canvas.drawRect(screen, Paint()..color = Colors.black.withValues(alpha: 0.94 * darkness));
      final cut = Paint()..blendMode = BlendMode.dstOut;
      // A small glow round the ship…
      final glowR = 2.4 * pxPerMeter;
      canvas.drawCircle(
        shipScreen,
        glowR,
        cut
          ..shader = ui.Gradient.radial(
            shipScreen,
            glowR,
            [Colors.white, Colors.white.withValues(alpha: 0)],
          ),
      );
      // …and a headlamp cone out of the nose.
      final reach = 8.5 * pxPerMeter;
      const half = 0.42;
      final dir = noseAngle - math.pi / 2;
      final cone = Path()
        ..moveTo(shipScreen.dx, shipScreen.dy)
        ..arcTo(Rect.fromCircle(center: shipScreen, radius: reach), dir - half, half * 2, false)
        ..close();
      canvas.drawPath(
        cone,
        cut
          ..shader = ui.Gradient.radial(
            shipScreen,
            reach,
            [Colors.white, Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)],
            [0, 0.55, 1],
          ),
      );
      canvas.restore();
    }
  }
}

/// Spore Trip's warp: the world is rendered to an image and redrawn through
/// `shaders/spore.frag` (waves, colour split, hue drift).
class SporePostProcess extends PostProcess {
  SporePostProcess(ui.FragmentProgram program, this.amount) : _shader = program.fragmentShader();

  final ui.FragmentShader _shader;
  final double Function() amount;
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void postProcess(Vector2 size, Canvas canvas) {
    final a = amount();
    if (a <= 0.001) {
      renderSubtree(canvas);
      return;
    }
    // Half the device resolution (at least 1×): the warp hides it, and the
    // offscreen pass every frame is the cost of this effect.
    final res = math.max(1.0, pixelRatio / 2);
    final recorder = ui.PictureRecorder();
    final inner = Canvas(recorder)..scale(res);
    renderSubtree(inner);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.x * res).ceil(),
      (size.y * res).ceil(),
    );
    picture.dispose();
    _shader
      ..setFloat(0, size.x)
      ..setFloat(1, size.y)
      ..setFloat(2, _t)
      ..setFloat(3, a)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size.toSize(), Paint()..shader = _shader);
    image.dispose();
  }
}
