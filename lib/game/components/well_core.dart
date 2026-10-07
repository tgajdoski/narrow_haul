import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Solid planetoid at the heart of a [GravityWellSpec]. Static terrain with a
/// [WallTag], so touching it is a crash like any wall; cargo bounces off it.
/// The pull itself comes from the force field system.
class WellCore extends BodyComponent {
  WellCore({required this.spec, required this.theme}) : super(renderBody: false);

  final GravityWellSpec spec;
  final ThemeSpec theme;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef()
        ..position = Vector2(spec.center.x, spec.center.y)
        ..type = BodyType.static,
    );
    b.createFixture(
      FixtureDef(
        CircleShape()..radius = spec.coreRadius,
        friction: 0.35,
        userData: const WallTag(),
        filter: filterWall(),
      ),
    );
    return b;
  }

  @override
  void render(Canvas canvas) {
    final r = spec.coreRadius;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    // Lit sphere: rock palette shaded toward a rim of the accent glow.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: [
            Color.lerp(theme.rockFill, Colors.white, 0.25)!,
            theme.rockFill,
            theme.rockEdge,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    // A few craters so it reads as a body, not a button.
    final crater = Paint()..color = theme.rockEdge.withValues(alpha: 0.45);
    for (final (a, d, s) in const [(0.6, 0.45, 0.18), (2.4, 0.5, 0.13), (4.1, 0.3, 0.1)]) {
      canvas.drawCircle(Offset(math.cos(a) * r * d, math.sin(a) * r * d), r * s, crater);
    }
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..color = theme.uiAccent.withValues(alpha: 0.7),
    );
  }
}
