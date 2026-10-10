import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/combat/aim.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/salvage/salvage.dart' show kFlareTempo;
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';

/// Shell color for enemy fire — warm and readable on every theme.
const Color kEnemyShellColor = Color(0xFFFF5252);

/// Wall-mounted defence turret (Thrust's limpet gun). The dome is solid
/// [WallTag] rock — flying into it is a crash like any wall. Holds fire until
/// the ship launches, needs line of sight (the cargo pod is valid cover), and
/// telegraphs each shot with a short muzzle glow.
class Turret extends BodyComponent implements Shootable {
  Turret({required this.spec, required this.theme, required this.host})
      : _aim = spec.facing,
        _cooldown = spec.cooldown * 0.6 + spec.phase,
        _rng = math.Random(spec.base.x.round() * 73 + spec.base.y.round()),
        super(renderBody: false, priority: 5);

  final TurretSpec spec;
  final ThemeSpec theme;
  final CombatHost host;
  final math.Random _rng;

  static const double domeRadius = kTurretDomeRadius;
  static const double barrelLength = 0.6;

  /// Max barrel slew (rad/s) — fast pilots can outrun the aim.
  static const double slewRate = 1.6;

  /// Muzzle glow before a shot, so every shell is telegraphed.
  static const double windup = 0.35;

  double _aim;
  double _cooldown;
  double _windup = 0;
  double _flash = 1;
  int _hits = 0;
  @override
  bool destroyed = false;

  Vector2 get _base => Vector2(spec.base.x, spec.base.y);

  Vector2 _muzzle(double angle) =>
      _base + Vector2(math.cos(angle), math.sin(angle)) * (domeRadius + barrelLength);

  @override
  Body createBody() {
    final b = world.createBody(BodyDef()
      ..position = _base
      ..type = BodyType.static);
    // Half-dome polygon facing out of the wall, sunk a little into the rock.
    final verts = <Vector2>[];
    const n = 7;
    for (var i = 0; i <= n; i++) {
      final a = spec.facing - math.pi / 2 + math.pi * i / n;
      verts.add(Vector2(math.cos(a), math.sin(a)) * domeRadius);
    }
    b.createFixture(FixtureDef(
      PolygonShape()..set(verts),
      userData: const WallTag(),
      filter: filterWall(),
    ));
    b.userData = this;
    return b;
  }

  @override
  void takeHit({int damage = 1, bool heavy = false}) {
    if (destroyed) return;
    _hits += damage;
    _flash = 0;
    if (_hits >= spec.hp) {
      destroyed = true;
      host.onTurretDestroyed(Offset(spec.base.x, spec.base.y));
    }
  }

  /// Could this turret shoot at a ship at [p] (range, arc, line of sight)?
  /// Used by the route guide to mark the stretch it covers.
  bool covers(Vector2 p) {
    if (destroyed) return false;
    final to = p - _base;
    if (to.length > spec.range) return false;
    final bearing = math.atan2(to.y, to.x);
    if (angleDelta(spec.facing, bearing).abs() > spec.aimArc) return false;
    return hasLineOfSight(world, _muzzle(bearing), p, ignore: body);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _flash += dt;
    if (destroyed) return;
    final ship = host.combatShip;
    final offline = host.turretsDisabled;
    if (offline) {
      // Barrel droops toward the wall's "down" side while powered off.
      _aim += angleDelta(_aim, spec.facing + 0.6) * math.min(1, dt * 2);
      _windup = 0;
      return;
    }
    if (ship == null || !ship.isMounted || !host.combatLive) {
      _windup = 0;
      return;
    }
    _cooldown -= dt * (host.shipFlared ? kFlareTempo : 1);

    final target = ship.body.position;
    final toShip = target - _base;
    final dist = toShip.length;
    final bearing = math.atan2(toShip.y, toShip.x);
    final inArc = angleDelta(spec.facing, bearing).abs() <= spec.aimArc;
    final muzzle = _muzzle(_aim);
    final visible = !host.shipCloaked &&
        dist <= spec.range &&
        inArc &&
        hasLineOfSight(world, muzzle, target, ignore: body);

    if (!visible) {
      _windup = 0;
      return;
    }

    final v = ship.body.linearVelocity;
    var want = leadAngle(muzzle.x, muzzle.y, target.x, target.y, v.x, v.y, spec.shellSpeed);
    // Keep the barrel inside its arc.
    final off = angleDelta(spec.facing, want).clamp(-spec.aimArc, spec.aimArc);
    want = spec.facing + off;
    final turn = angleDelta(_aim, want);
    final maxStep = slewRate * dt;
    _aim += turn.clamp(-maxStep, maxStep);

    if (_cooldown <= 0 && turn.abs() < 0.2) {
      _windup += dt;
      if (_windup >= windup) _fire();
    }
  }

  void _fire() {
    _windup = 0;
    _cooldown = spec.cooldown * (0.85 + 0.3 * _rng.nextDouble());
    final spread = (_rng.nextDouble() - 0.5) * 0.12;
    final a = _aim + spread;
    host.spawnShell(Shell(
      position: _muzzle(_aim),
      velocity: Vector2(math.cos(a), math.sin(a)) * spec.shellSpeed,
      fromPlayer: false,
      host: host,
      world: world,
      color: kEnemyShellColor,
    ));
  }

  @override
  void render(Canvas canvas) {
    // Body-local (the body sits at the base, angle 0).
    final dir = Offset(math.cos(_aim), math.sin(_aim));
    final barrelEnd = dir * (domeRadius + barrelLength);
    final baseColor = destroyed ? theme.rockEdge : const Color(0xFF3A4150);
    if (!destroyed) {
      canvas.drawLine(
        dir * (domeRadius * 0.4),
        barrelEnd,
        Paint()
          ..color = const Color(0xFF8A93A6)
          ..strokeWidth = 0.17
          ..strokeCap = StrokeCap.butt,
      );
    }
    final dome = Path();
    final rect = Rect.fromCircle(center: Offset.zero, radius: domeRadius);
    dome.addArc(rect, spec.facing - math.pi / 2, math.pi);
    dome.close();
    canvas.drawPath(dome, Paint()..color = baseColor);
    canvas.drawPath(
      dome,
      Paint()
        ..color = (destroyed ? theme.rockHighlight : kEnemyShellColor)
            .withValues(alpha: destroyed ? 0.5 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    );
    // Status light: red when tracking, dim when offline/destroyed.
    final light = destroyed
        ? null
        : host.turretsDisabled
            ? const Color(0x664FC3F7)
            : kEnemyShellColor;
    if (light != null) {
      canvas.drawCircle(Offset(math.cos(spec.facing), math.sin(spec.facing)) * 0.22, 0.09,
          Paint()..color = light);
    }
    if (_windup > 0) {
      final t = (_windup / windup).clamp(0.0, 1.0);
      canvas.drawCircle(
        barrelEnd,
        0.08 + 0.12 * t,
        Paint()
          ..color = kEnemyShellColor.withValues(alpha: 0.35 + 0.5 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.06),
      );
    }
    final f = flashAlpha(_flash);
    if (f > 0) {
      canvas.drawCircle(Offset.zero, domeRadius * 1.2,
          Paint()..color = Colors.white.withValues(alpha: 0.7 * f));
    }
  }
}

/// Reactor core (Thrust's power plant). A few hits knock the turrets out for
/// a while; destroying it triggers the meltdown escape. Solid like rock.
class Reactor extends BodyComponent implements Shootable {
  Reactor({required this.spec, required this.theme, required this.host})
      : super(renderBody: false, priority: 5);

  final ReactorSpec spec;
  final ThemeSpec theme;
  final CombatHost host;

  int _hits = 0;
  double _t = 0;
  double _flash = 1;
  @override
  bool destroyed = false;

  double get health => (1 - _hits / spec.hp).clamp(0.0, 1.0);

  @override
  Body createBody() {
    final b = world.createBody(BodyDef()
      ..position = Vector2(spec.center.x, spec.center.y)
      ..type = BodyType.static);
    b.createFixture(FixtureDef(
      CircleShape()..radius = spec.radius,
      userData: const WallTag(),
      filter: filterWall(),
    ));
    b.userData = this;
    return b;
  }

  @override
  void takeHit({int damage = 1, bool heavy = false}) {
    if (destroyed) return;
    final before = _hits;
    _hits = math.min(spec.hp, _hits + damage);
    _flash = 0;
    if (before < spec.disableHits && _hits >= spec.disableHits && _hits < spec.hp) {
      host.onReactorDisabledTurrets(spec.disableSeconds);
    }
    if (_hits >= spec.hp) {
      destroyed = true;
      host.onReactorDestroyed(Offset(spec.center.x, spec.center.y), spec.escapeSeconds);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _flash += dt;
  }

  @override
  void render(Canvas canvas) {
    final r = spec.radius;
    // Housing.
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFF2B303B));
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = theme.padAccent.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06,
    );
    if (destroyed) {
      // Critical: flickering, overheated core.
      final flicker = 0.55 + 0.45 * math.sin(_t * 22).abs();
      canvas.drawCircle(
        Offset.zero,
        r * 0.75,
        Paint()
          ..color = const Color(0xFFFF3D00).withValues(alpha: flicker)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.15),
      );
      final crack = Paint()
        ..color = const Color(0xFFFFD180)
        ..strokeWidth = 0.04;
      for (var i = 0; i < 5; i++) {
        final a = i * 1.3 + 0.4;
        canvas.drawLine(Offset.zero, Offset(math.cos(a), math.sin(a)) * r, crack);
      }
      return;
    }
    // Pulsing core, slower as it takes damage.
    final pulse = 0.5 + 0.5 * math.sin(_t * (2.5 + 4 * (1 - health)));
    canvas.drawCircle(
      Offset.zero,
      r * (0.45 + 0.08 * pulse),
      Paint()
        ..color = const Color(0xFF69F0AE).withValues(alpha: 0.6 + 0.4 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1),
    );
    // Health ring.
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.82),
      -math.pi / 2,
      2 * math.pi * health,
      false,
      Paint()
        ..color = Color.lerp(kEnemyShellColor, const Color(0xFF69F0AE), health)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.07,
    );
    final f = flashAlpha(_flash);
    if (f > 0) {
      canvas.drawCircle(Offset.zero, r * 1.15,
          Paint()..color = Colors.white.withValues(alpha: 0.7 * f));
    }
  }
}

/// Fuel canister: fly through it to top up the tank. Distance-checked
/// against the hull each frame — no physics body needed.
class FuelCell extends Component {
  FuelCell({required this.spec, required this.host, required this.accent})
      : super(priority: 6);

  final FuelCellSpec spec;
  final CombatHost host;
  final Color accent;

  static const double pickupRadius = 0.8;

  double _t = 0;
  bool collected = false;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (collected) return;
    final ship = host.combatShip;
    if (ship == null || !ship.isMounted || !host.combatLive) return;
    final p = ship.body.position;
    final dx = p.x - spec.pos.x;
    final dy = p.y - spec.pos.y;
    if (dx * dx + dy * dy <= pickupRadius * pickupRadius) {
      collected = true;
      host.onFuelCollected(spec.amount, Offset(spec.pos.x, spec.pos.y));
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final bob = math.sin(_t * 2.2) * 0.08;
    // Drawn around the origin at 1.6× so it reads next to the big ship art.
    canvas.save();
    canvas.translate(spec.pos.x, spec.pos.y + bob);
    canvas.scale(1.6);
    const c = Offset.zero;
    canvas.drawCircle(
      c,
      0.45,
      Paint()
        ..color = accent.withValues(alpha: 0.18 + 0.1 * math.sin(_t * 3))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.2),
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 0.34, height: 0.46),
      const Radius.circular(0.06),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF1E2A38));
    canvas.drawRRect(
      body,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04,
    );
    // Fill level band + cap.
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(0, 0.07), width: 0.22, height: 0.18),
      Paint()..color = accent.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(0, -0.27), width: 0.14, height: 0.07),
      Paint()..color = accent,
    );
    canvas.restore();
  }
}

/// Supply crate: a random weapon's ammo, found mid-level on flights with an
/// unarmed ship. Fly through it like a fuel canister; the ammo lasts this
/// flight only (and, being found, never costs a star).
class SupplyCrate extends Component {
  SupplyCrate({
    required this.pos,
    required this.weapon,
    required this.units,
    required this.host,
    required this.accent,
    required this.onCollected,
  }) : super(priority: 6);

  final Offset pos;
  final WeaponSpec weapon;
  final double units;
  final CombatHost host;
  final Color accent;
  final void Function(SupplyCrate crate) onCollected;

  static const double pickupRadius = 0.9;

  double _t = 0;
  bool collected = false;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (collected) return;
    final ship = host.combatShip;
    if (ship == null || !ship.isMounted || !host.combatLive) return;
    final p = ship.body.position;
    final dx = p.x - pos.dx;
    final dy = p.y - pos.dy;
    if (dx * dx + dy * dy <= pickupRadius * pickupRadius) {
      collected = true;
      onCollected(this);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final bob = math.sin(_t * 2.0) * 0.08;
    canvas.save();
    canvas.translate(pos.dx, pos.dy + bob);
    canvas.rotate(math.sin(_t * 1.3) * 0.12);
    canvas.scale(1.6);
    const c = Offset.zero;
    canvas.drawCircle(
      c,
      0.5,
      Paint()
        ..color = accent.withValues(alpha: 0.2 + 0.1 * math.sin(_t * 3.4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.22),
    );
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: 0.5, height: 0.36),
      const Radius.circular(0.04),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0xFF3B3326));
    final edge = Paint()
      ..color = const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035;
    canvas.drawRRect(box, edge);
    // Banding + a warning chevron: reads as "ordnance", not fuel.
    canvas.drawLine(const Offset(-0.25, -0.06), const Offset(0.25, -0.06), edge);
    final chevron = Path()
      ..moveTo(-0.09, 0.12)
      ..lineTo(0, 0.02)
      ..lineTo(0.09, 0.12);
    canvas.drawPath(
      chevron,
      Paint()
        ..color = const Color(0xFFFF5252)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04,
    );
    canvas.restore();
  }
}
