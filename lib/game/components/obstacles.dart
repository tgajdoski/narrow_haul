import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/obstacle_paths.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Builds the matching component for an [ObstacleSpec]. Defences (turrets,
/// reactor) talk to the running game through [host].
BodyComponent obstacleFromSpec(ObstacleSpec spec, ThemeSpec theme, CombatHost host) {
  return switch (spec) {
    RotatingBarSpec s => RotatingBar(spec: s, theme: theme, host: host),
    PendulumSpec s => Pendulum(spec: s, theme: theme, host: host),
    SlidingBlockSpec s => SlidingBlock(spec: s, theme: theme, host: host),
    TurretSpec s => Turret(spec: s, theme: theme, host: host),
    ReactorSpec s => Reactor(spec: s, theme: theme, host: host),
  };
}

/// All obstacles carry a WallTag fixture, so ship contact routes through the
/// existing crash handling and cargo gets physically batted around.

/// Moving machinery can be wrecked by heavy weapons (charges, bombs, laser,
/// missiles, flak — never the Talon's cannon, which just bounces off). A
/// wrecked obstacle leaves the world; its body goes with it.
mixin Wreckable on BodyComponent implements Shootable {
  CombatHost get host;

  /// Heavy hits it takes.
  int get maxHp;

  int _damage = 0;
  double _flash = 1;

  @override
  bool destroyed = false;

  @override
  void takeHit({int damage = 1, bool heavy = false}) {
    if (destroyed || !heavy) return;
    _damage += damage;
    _flash = 0;
    if (_damage >= maxHp) {
      destroyed = true;
      final p = body.position;
      host.onObstacleDestroyed(Offset(p.x, p.y));
      removeFromParent();
    }
  }

  void tickFlash(double dt) => _flash += dt;

  /// Body-local white flash of [radius] after a hit.
  void renderHitFlash(Canvas canvas, double radius) {
    final f = flashAlpha(_flash);
    if (f <= 0) return;
    canvas.drawCircle(Offset.zero, radius,
        Paint()..color = Colors.white.withValues(alpha: 0.6 * f));
  }
}

/// Kinematic bar spinning at constant angular velocity — drift-free.
class RotatingBar extends BodyComponent with Wreckable {
  RotatingBar({required this.spec, required this.theme, required this.host})
      : super(renderBody: false);

  final RotatingBarSpec spec;
  final ThemeSpec theme;
  @override
  final CombatHost host;

  @override
  int get maxHp => 4;

  @override
  void update(double dt) {
    super.update(dt);
    tickFlash(dt);
  }

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
    b.userData = this;
    return b;
  }

  @override
  void render(Canvas canvas) {
    _renderHazardBox(canvas, spec.halfLength, spec.thickness, theme);
    canvas.drawCircle(Offset.zero, spec.thickness * 1.4,
        Paint()..color = theme.padAccent.withValues(alpha: 0.9));
    renderHitFlash(canvas, spec.thickness * 3);
  }
}

/// Bob swinging on an analytic arc via velocity tracking (never teleported,
/// so contacts stay physically correct and the path is frame-rate proof).
class Pendulum extends BodyComponent with Wreckable {
  Pendulum({required this.spec, required this.theme, required this.host})
      : super(renderBody: false);

  final PendulumSpec spec;
  final ThemeSpec theme;
  @override
  final CombatHost host;

  @override
  int get maxHp => 3;
  double _t = 0;

  /// Seconds since spawn (the path's clock).
  double get time => _t;

  Vector2 _bobAt(double t) {
    final p = pendulumBobAt(spec, t);
    return Vector2(p.x, p.y);
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
    b.userData = this;
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    tickFlash(dt);
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
    renderHitFlash(canvas, spec.bobRadius * 1.2);
  }
}

/// Block oscillating between two points on a cosine ease (velocity-tracked).
class SlidingBlock extends BodyComponent with Wreckable {
  SlidingBlock({required this.spec, required this.theme, required this.host})
      : super(renderBody: false);

  final SlidingBlockSpec spec;
  final ThemeSpec theme;
  @override
  final CombatHost host;

  @override
  int get maxHp => 5;
  double _t = 0;

  /// Seconds since spawn (the path's clock).
  double get time => _t;

  Vector2 _posAt(double t) {
    final p = slidingBlockAt(spec, t);
    return Vector2(p.x, p.y);
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
    b.userData = this;
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    tickFlash(dt);
    if (dt <= 0) return;
    _t += dt;
    final target = _posAt(_t);
    body.linearVelocity = (target - body.position) / dt;
  }

  @override
  void render(Canvas canvas) {
    _renderHazardBox(canvas, spec.halfW, spec.halfH, theme);
    renderHitFlash(canvas, spec.halfW + spec.halfH);
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
