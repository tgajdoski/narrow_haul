import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/tags.dart';

/// The nearest solid thing (rock, obstacle) around the ship.
class RockNearby {
  RockNearby(this.gap, this.normal, this.approach);

  /// Distance from the hull's own edge to the surface (m).
  final double gap;

  /// Surface normal at the hit, pointing out of the rock toward the ship.
  final Vector2 normal;

  /// The ship's velocity into that surface (m/s, ≤ 0 = moving away).
  final double approach;
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
      best = RockNearby(gap, normal, -body.linearVelocity.dot(normal));
    }
  }
  return best;
}

const int _rays = 12;

class _NearRay extends RayCastCallback {
  _NearRay(this.ship);
  final Body ship;
  bool hit = false;
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
    fraction = frac;
    normal.setFrom(n);
    return frac; // keep only the nearest
  }
}
