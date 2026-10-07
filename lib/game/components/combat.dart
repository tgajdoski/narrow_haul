import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
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
}

/// Something a player shell can damage (turrets, reactor). Set as the body's
/// `userData`.
abstract interface class Shootable {
  void takeHit();
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
  })  : pos = position.clone(),
        vel = velocity.clone(),
        super(priority: 1050);

  final bool fromPlayer;
  final CombatHost host;
  final Forge2DWorld world;
  final Color color;
  final Vector2 pos;
  final Vector2 vel;

  static const double radius = 0.1;
  static const double lifetime = 2.6;

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
      _expire();
      return;
    }
    final next = pos + vel * dt;
    final hit = _ShellRay(fromPlayer: fromPlayer);
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

  Fixture? _overlapAt(Vector2 p) {
    if (!fromPlayer) {
      final ship = host.combatShip;
      if (ship != null && ship.isMounted) {
        for (final f in ship.body.fixtures) {
          if (!f.isSensor && f.testPoint(p)) return f;
        }
      }
    }
    final cargo = host.combatCargo;
    if (cargo != null) {
      for (final f in cargo.fixtures) {
        if (!f.isSensor && f.testPoint(p)) return f;
      }
    }
    return null;
  }

  void _impact(Fixture fixture, Vector2 at) {
    final owner = fixture.body.userData;
    if (fixture.userData is ShipTag || owner is ShipBody) {
      if (!fromPlayer) host.onShipShot();
    } else if (fixture.userData is CargoTag || owner is CargoTag) {
      final dir = vel.normalized();
      fixture.body.applyLinearImpulse(dir..scale(cargoImpulse), point: at);
    } else if (fromPlayer && owner is Shootable) {
      owner.takeHit();
    }
    pos.setFrom(at);
    _expire();
  }

  void _expire() {
    _spent = true;
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
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
  _ShellRay({required this.fromPlayer});
  final bool fromPlayer;
  Fixture? fixture;
  Vector2? point;

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 normal, double fraction) {
    if (f.isSensor) return -1;
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
