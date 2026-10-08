import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';

/// What turrets, reactors, shells and pickups need from the running game.
/// Implemented by `NarrowHaulGame`; kept as an interface so the defences
/// never reach into game internals.
abstract interface class CombatHost {
  /// The ship to shoot at / collect with; null between levels.
  ShipBody? get combatShip;

  /// Cargo body (shells shove it, it blocks turret line of sight).
  Body? get combatCargo;

  /// True while a flight is live and the ship has launched — defences hold
  /// fire on the start pad and after a crash or delivery.
  bool get combatLive;

  /// Reactor hits knocked every turret offline.
  bool get turretsDisabled;

  void spawnShell(Shell shell);

  /// An enemy shell hit the ship.
  void onShipShot();
  void onTurretDestroyed(Offset at);
  void onReactorDisabledTurrets(double seconds);
  void onReactorDestroyed(Offset at, double escapeSeconds);
  void onFuelCollected(double amount, Offset at);

  /// A special weapon went off at [at]: damages everything shootable within
  /// its blast radius, shoves the pod and opens the rock.
  void detonate(Vector2 at, WeaponSpec weapon);

  /// A moving obstacle (bar, pendulum, block) was wrecked.
  void onObstacleDestroyed(Offset at);
}

/// Something a player shell can damage (turrets, reactor, and — with a
/// [heavy] weapon — moving obstacles). Set as the body's `userData`.
abstract interface class Shootable {
  /// [damage] hits at once. [heavy] weapons (everything but the Talon's
  /// cannon) also break machinery.
  void takeHit({int damage = 1, bool heavy = false});

  /// Already wrecked (blasts skip it).
  bool get destroyed;
}

/// Cannon shell. Not a physics body: it moves analytically and raycasts its
/// path each frame, so it never tunnels through thin chain-shape walls and
/// never shoves anything it hits except deliberately (cargo).
class Shell extends Component {
  Shell({
    required Vector2 position,
    required Vector2 velocity,
    required this.fromPlayer,
    required this.host,
    required this.world,
    required this.color,
    this.weapon,
    this.gravity,
    this.homing,
    this.lifetime = 2.6,
  })  : pos = position.clone(),
        vel = velocity.clone(),
        super(priority: 1050);

  final bool fromPlayer;

  /// Special-weapon round (bomb, missile, flak pellet); null = cannon/enemy.
  final WeaponSpec? weapon;

  /// Local acceleration at a point (bombs fall); null = straight line.
  final Vector2 Function(Vector2 p)? gravity;

  /// Seeker: the current target, or null to fly straight.
  final Vector2? Function(Vector2 from)? homing;
  final double lifetime;
  final CombatHost host;
  final Forge2DWorld world;
  final Color color;
  final Vector2 pos;
  final Vector2 vel;

  static const double radius = 0.1;

  /// Seeker turn rate (rad/s) and top speed.
  static const double _seekTurn = 3.2;
  static const double _seekMaxSpeed = 8;

  /// Impulse (N·s) an enemy shell gives the cargo — enough to swing it.
  static const double cargoImpulse = 0.05;

  double _age = 0;
  bool _spent = false;

  @override
  void update(double dt) {
    super.update(dt);
    if (_spent) return;
    _age += dt;
    if (_age > lifetime) {
      // A bomb or missile that runs out still goes off.
      if (weapon != null && weapon!.blastRadius > 0) {
        host.detonate(pos, weapon!);
      }
      _expire();
      return;
    }
    final g = gravity;
    if (g != null) vel.add(g(pos) * dt);
    final seek = homing;
    if (seek != null && _age > 0.15) _steer(seek(pos), dt);
    final next = pos + vel * dt;
    final hit = _ShellRay(fromPlayer: fromPlayer, ignore: _passesPod ? host.combatCargo : null);
    if ((next - pos).length2 > 1e-10) world.raycast(hit, pos, next);
    var fixture = hit.fixture;
    // A fast ship can sweep over a slow shell inside one step; catch shells
    // that end up inside the hull or the pod.
    fixture ??= _overlapAt(next);
    if (fixture == null) {
      pos.setFrom(next);
      return;
    }
    _impact(fixture, hit.point ?? next);
  }

  /// Bombs fall past the pod hanging under the ship instead of bursting on
  /// it the moment they're released.
  bool get _passesPod => weapon?.kind == WeaponKind.bomb;

  void _steer(Vector2? target, double dt) {
    final speed = vel.length;
    final want = speed + 6 * dt;
    if (target == null) {
      vel.scale(math.min(want, _seekMaxSpeed) / math.max(speed, 1e-6));
      return;
    }
    final heading = math.atan2(vel.y, vel.x);
    final to = target - pos;
    var d = math.atan2(to.y, to.x) - heading;
    d = (d + math.pi) % (2 * math.pi) - math.pi;
    final a = heading + d.clamp(-_seekTurn * dt, _seekTurn * dt);
    final v = math.min(want, _seekMaxSpeed);
    vel.setValues(math.cos(a) * v, math.sin(a) * v);
  }

  Fixture? _overlapAt(Vector2 p) {
    if (!fromPlayer) {
      final ship = host.combatShip;
      if (ship != null && ship.isMounted) {
        for (final f in ship.body.fixtures) {
          if (!f.isSensor && f.testPoint(p)) return f;
        }
      }
    }
    final cargo = _passesPod ? null : host.combatCargo;
    if (cargo != null) {
      for (final f in cargo.fixtures) {
        if (!f.isSensor && f.testPoint(p)) return f;
      }
    }
    return null;
  }

  void _impact(Fixture fixture, Vector2 at) {
    final owner = fixture.body.userData;
    final w = weapon;
    pos.setFrom(at);
    if (w != null && w.blastRadius > 0) {
      // Bombs and missiles burst on whatever they touch (the blast does
      // the damage, including to what was hit).
      host.detonate(at, w);
    } else if (fixture.userData is ShipTag || owner is ShipBody) {
      if (!fromPlayer) host.onShipShot();
    } else if (fixture.userData is CargoTag || owner is CargoTag) {
      final dir = vel.normalized();
      fixture.body.applyLinearImpulse(dir..scale(cargoImpulse), point: at);
    } else if (fromPlayer && owner is Shootable) {
      owner.takeHit(damage: w?.damage ?? 1, heavy: w?.heavy ?? false);
    }
    _expire();
  }

  void _expire() {
    _spent = true;
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    switch (weapon?.kind) {
      case WeaponKind.bomb:
        _renderBomb(canvas);
        return;
      case WeaponKind.seeker:
        _renderMissile(canvas);
        return;
      default:
        _renderRound(canvas);
    }
  }

  void _renderBomb(Canvas canvas) {
    final c = Offset(pos.x, pos.y);
    canvas.drawCircle(c, 0.17, Paint()..color = const Color(0xFF2B303B));
    canvas.drawCircle(
      c,
      0.17,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04,
    );
    if ((_age * 6).floor().isEven) {
      canvas.drawCircle(c, 0.06, Paint()..color = const Color(0xFFFF5252));
    }
  }

  void _renderMissile(Canvas canvas) {
    final dir = vel.normalized();
    final tail = Offset(pos.x - dir.x * 0.32, pos.y - dir.y * 0.32);
    final tip = Offset(pos.x, pos.y);
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = const Color(0xFFE0E6F0)
        ..strokeWidth = 0.09
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(tail.dx - dir.x * 0.08, tail.dy - dir.y * 0.08),
      0.08 + 0.03 * math.sin(_age * 40),
      Paint()
        ..color = const Color(0xFFFFB74D).withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.05),
    );
  }

  void _renderRound(Canvas canvas) {
    final tail = vel.normalized()..scale(-0.28);
    canvas.drawLine(
      Offset(pos.x + tail.x, pos.y + tail.y),
      Offset(pos.x, pos.y),
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = radius * 1.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(pos.x, pos.y),
      radius * 1.9,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08),
    );
    canvas.drawCircle(Offset(pos.x, pos.y), radius, Paint()..color = Colors.white);
  }
}

/// Closest solid fixture along a shell's path. Sensors (hook, pads) never
/// stop a shell, and a shell never hits its own side's hull.
class _ShellRay extends RayCastCallback {
  _ShellRay({required this.fromPlayer, this.ignore});
  final bool fromPlayer;
  final Body? ignore;
  Fixture? fixture;
  Vector2? point;

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 normal, double fraction) {
    if (f.isSensor || f.body == ignore) return -1;
    if (fromPlayer && (f.userData is ShipTag || f.body.userData is ShipBody)) {
      return -1;
    }
    fixture = f;
    point = p.clone();
    return fraction; // clip: keep looking for anything closer
  }
}

/// True when nothing solid (terrain, obstacles, cargo) blocks the segment
/// [from]→[to]. Fixtures in [ignore] and the ship itself are transparent.
bool hasLineOfSight(Forge2DWorld world, Vector2 from, Vector2 to, {Body? ignore}) {
  if ((to - from).length2 < 1e-8) return true;
  final ray = _SightRay(ignore);
  world.raycast(ray, from, to);
  return !ray.blocked;
}

class _SightRay extends RayCastCallback {
  _SightRay(this.ignore);
  final Body? ignore;
  bool blocked = false;

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 normal, double fraction) {
    if (f.isSensor || f.body == ignore) return -1;
    if (f.userData is ShipTag || f.body.userData is ShipBody) return -1;
    blocked = true;
    return 0;
  }
}

/// Small helper for the hit flash shared by turrets and reactors.
double flashAlpha(double t) => math.max(0, 1 - t / 0.18);
