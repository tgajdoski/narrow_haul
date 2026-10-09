import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/tags.dart';

/// The nearest solid thing (rock, obstacle) around the ship.
class RockNearby {
  RockNearby(this.gap, this.normal, this.approach, {this.lethal = false});

  /// Distance from the hull's own edge to the surface (m).
  final double gap;

  /// Surface normal at the hit, pointing out of the rock toward the ship.
  final Vector2 normal;

  /// The ship's velocity into that surface (m/s, ≤ 0 = moving away).
  final double approach;

  /// Not forgiving rock (a moving obstacle, turret, reactor, well core):
  /// any touch crashes, whatever the speed.
  final bool lethal;
}

/// Finds the closest [WallTag] surface within [range] of the hull with
/// [_rays] raycasts from the ship's centre. The hull isn't round, so the
/// gap subtracts how far the hull itself reaches in each ray's direction.
RockNearby? probeRockNearby(Forge2DWorld world, ShipBody ship, {double range = 1.0}) {
  final body = ship.body;
  final spec = ship.spec;
  final hull = [
    for (final poly in spec.hullPolygons)
      for (final (x, y) in poly) Vector2(x, y),
  ];
  final from = body.position;
  final ray = _NearRay(body);
  RockNearby? best;
  for (var i = 0; i < _rays; i++) {
    final a = i * 2 * math.pi / _rays;
    final dir = Vector2(math.cos(a), math.sin(a));
    // How far the hull reaches toward [dir] (support distance).
    final local = body.localVector(dir);
    var reach = 0.0;
    for (final v in hull) {
      reach = math.max(reach, v.dot(local));
    }
    final length = reach + range;
    ray.reset();
    world.raycast(ray, from, from + dir * length);
    if (!ray.hit) continue;
    final gap = ray.fraction * length - reach;
    if (best == null || gap < best.gap) {
      final normal = ray.normal.clone();
      best = RockNearby(
        gap,
        normal,
        -body.linearVelocity.dot(normal),
        lethal: !ray.rock,
      );
    }
  }
  return best;
}

const int _rays = 12;

/// Gap (m, from the hull's edge) to the nearest [WallTag] surface along
/// [dir] (unit) and ±15° either side, within [range]; null when clear.
/// The camera uses it to see a wall coming at speed.
double? probeAhead(Forge2DWorld world, ShipBody ship, Vector2 dir, {double range = 8}) {
  final body = ship.body;
  final from = body.position;
  final ray = _NearRay(body);
  double? best;
  for (final turn in const [0.0, 0.26, -0.26]) {
    final c = math.cos(turn), s = math.sin(turn);
    final d = Vector2(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    final local = body.localVector(d);
    var reach = 0.0;
    for (final poly in ship.spec.hullPolygons) {
      for (final (x, y) in poly) {
        reach = math.max(reach, x * local.x + y * local.y);
      }
    }
    final length = reach + range;
    ray.reset();
    world.raycast(ray, from, from + d * length);
    if (!ray.hit) continue;
    final gap = math.max(0.0, ray.fraction * length - reach);
    if (best == null || gap < best) best = gap;
  }
  return best;
}

class _NearRay extends RayCastCallback {
  _NearRay(this.ship);
  final Body ship;
  bool hit = false;
  bool rock = false;
  double fraction = 1;
  final Vector2 normal = Vector2.zero();

  void reset() {
    hit = false;
    fraction = 1;
  }

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 n, double frac) {
    if (f.isSensor || f.body == ship || f.userData is! WallTag) return -1;
    hit = true;
    rock = f.userData is RockTag;
    fraction = frac;
    normal.setFrom(n);
    return frac; // keep only the nearest
  }
}
