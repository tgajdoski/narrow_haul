import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Builds the matching component for an [ObstacleSpec].
BodyComponent obstacleFromSpec(ObstacleSpec spec, ThemeSpec theme) {
  return switch (spec) {
    RotatingBarSpec s => RotatingBar(spec: s, theme: theme),
    PendulumSpec s => Pendulum(spec: s, theme: theme),
    SlidingBlockSpec s => SlidingBlock(spec: s, theme: theme),
  };
}

/// All obstacles carry a WallTag fixture, so ship contact routes through the
/// existing crash handling and cargo gets physically batted around.

/// Kinematic bar spinning at constant angular velocity — drift-free.
class RotatingBar extends BodyComponent {
  RotatingBar({required this.spec, required this.theme})
      : super(renderBody: false);

  final RotatingBarSpec spec;
  final ThemeSpec theme;

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = Vector2(spec.center.x, spec.center.y)
      ..angle = spec.initialAngle
      ..type = BodyType.kinematic;
    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(spec.halfLength, spec.thickness),
        userData: const WallTag(),
        filter: filterWall(),
      ),
    );
    b.angularVelocity = spec.radPerSec;
    return b;
  }

  @override
  void render(Canvas canvas) {
    _renderHazardBox(canvas, spec.halfLength, spec.thickness, theme);
    canvas.drawCircle(Offset.zero, spec.thickness * 1.4,
        Paint()..color = theme.padAccent.withValues(alpha: 0.9));
  }
}

/// Bob swinging on an analytic arc via velocity tracking (never teleported,
/// so contacts stay physically correct and the path is frame-rate proof).
class Pendulum extends BodyComponent {
  Pendulum({required this.spec, required this.theme}) : super(renderBody: false);

  final PendulumSpec spec;
  final ThemeSpec theme;
  double _t = 0;

  Vector2 _bobAt(double t) {
    final theta =
        spec.amplitudeRad * math.cos(2 * math.pi * t / spec.periodSec + spec.phase);
    return Vector2(
      spec.pivot.x + spec.length * math.sin(theta),
      spec.pivot.y + spec.length * math.cos(theta),
    );
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = _bobAt(0)
      ..type = BodyType.kinematic;
    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        CircleShape()..radius = spec.bobRadius,
        userData: const WallTag(),
        filter: filterWall(),
      ),
    );
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) return;
    _t += dt;
    final target = _bobAt(_t);
    body.linearVelocity = (target - body.position) / dt;
  }

  @override
  void render(Canvas canvas) {
    // Body-local: pivot relative to the bob.
    final pivotLocal = Offset(
      spec.pivot.x - body.position.x,
      spec.pivot.y - body.position.y,
    );
    canvas.drawLine(
      pivotLocal,
      Offset.zero,
      Paint()
        ..color = theme.rockHighlight.withValues(alpha: 0.9)
        ..strokeWidth = 0.05,
    );
    canvas.drawCircle(pivotLocal, 0.12, Paint()..color = theme.rockEdge);
    canvas.drawCircle(
        Offset.zero, spec.bobRadius, Paint()..color = theme.rockEdge);
    canvas.drawCircle(
      Offset.zero,
      spec.bobRadius,
      Paint()
        ..color = theme.padAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06,
    );
  }
}

/// Block oscillating between two points on a cosine ease (velocity-tracked).
class SlidingBlock extends BodyComponent {
  SlidingBlock({required this.spec, required this.theme})
      : super(renderBody: false);

  final SlidingBlockSpec spec;
  final ThemeSpec theme;
  double _t = 0;

  Vector2 _posAt(double t) {
    final s = 0.5 - 0.5 * math.cos(2 * math.pi * (t / spec.periodSec + spec.phase));
    return Vector2(
      spec.from.x + (spec.to.x - spec.from.x) * s,
      spec.from.y + (spec.to.y - spec.from.y) * s,
    );
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = _posAt(0)
      ..type = BodyType.kinematic;
    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(spec.halfW, spec.halfH),
        userData: const WallTag(),
        filter: filterWall(),
      ),
    );
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) return;
    _t += dt;
    final target = _posAt(_t);
    body.linearVelocity = (target - body.position) / dt;
  }

  @override
  void render(Canvas canvas) {
    _renderHazardBox(canvas, spec.halfW, spec.halfH, theme);
  }
}

/// Shared hazard look: dark box with warning stripes in the theme accent.
void _renderHazardBox(Canvas canvas, double halfW, double halfH, ThemeSpec theme) {
  final rect = Rect.fromCenter(
      center: Offset.zero, width: halfW * 2, height: halfH * 2);
  canvas.drawRect(rect, Paint()..color = theme.rockEdge);
  canvas.save();
  canvas.clipRect(rect);
  final stripePaint = Paint()
    ..color = theme.padAccent.withValues(alpha: 0.35)
    ..strokeWidth = 0.12;
  final span = halfW + halfH;
  for (double d = -span; d <= span; d += 0.4) {
    canvas.drawLine(
        Offset(d - halfH, halfH), Offset(d + halfH, -halfH), stripePaint);
  }
  canvas.restore();
  canvas.drawRect(
    rect,
    Paint()
      ..color = theme.padAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05,
  );
}
