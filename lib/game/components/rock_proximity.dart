import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
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
  final hull = _scaledHull(ship.spec, ship.sizeMul);
  final from = body.position;
  final q = body.transform.q;
  final ray = _probeRay..ship = body;
  RockNearby? best;
  for (final dir in _rayDirs) {
    // How far the hull reaches toward [dir] (support distance), in the
    // body's frame (as Body.localVector).
    final lx = q.cos * dir.x + q.sin * dir.y;
    final ly = -q.sin * dir.x + q.cos * dir.y;
    var reach = 0.0;
    for (var j = 0; j < hull.length; j += 2) {
      reach = math.max(reach, hull[j] * lx + hull[j + 1] * ly);
    }
    final length = reach + range;
    ray.reset();
    _probeTo
      ..setFrom(dir)
      ..scale(length)
      ..add(from);
    world.raycast(ray, from, _probeTo);
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

/// Unit ray directions, evenly round the ship.
final List<Vector2> _rayDirs = [
  for (var i = 0; i < _rays; i++)
    Vector2(math.cos(i * 2 * math.pi / _rays), math.sin(i * 2 * math.pi / _rays)),
];

/// Reused every frame: the ray callback and the ray's end point.
final _NearRay _probeRay = _NearRay(null);
final Vector2 _probeTo = Vector2.zero();

/// The hull's vertices × [k] as x, y pairs, rebuilt only when the ship or
/// its size (salvage) changes.
List<double> _scaledHull(ShipSpec spec, double k) {
  if (!identical(spec, _hullSpec) || k != _hullK) {
    _hullSpec = spec;
    _hullK = k;
    _hullXY = [
      for (final poly in spec.hullPolygons)
        for (final (x, y) in poly) ...[x * k, y * k],
    ];
  }
  return _hullXY;
}

ShipSpec? _hullSpec;
double _hullK = 0;
List<double> _hullXY = const [];

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
        reach = math.max(reach, (x * local.x + y * local.y) * ship.sizeMul);
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
  Body? ship;
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
