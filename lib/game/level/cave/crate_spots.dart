import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Crates sit at least this far from the spawn, the pod and the pad.
const double kCrateAnchorClearance = 2.5;

/// Preferred detour band around the spawn → pod → pad route (m).
const double kCrateRouteMin = 1.0;
const double kCrateRouteMax = 6.0;

/// Supply-crate spots for a cave level: open (room for the ship to turn),
/// reachable from the spawn, clear of the anchors, of every moving
/// obstacle's sweep and of gravity-well cores — preferring a short detour
/// off the shortest route. Empty on levels with defences (armed ships have
/// their own gun). Deterministic; memoized per level and ship.
List<Pt> crateSpots(LevelSpec spec, {ShipSpec ship = kKestrel}) =>
    _cache['${spec.id}/${ship.id}'] ??= _spots(spec, ship, defended: false);

/// Mystery-salvage spots: the same rules as [crateSpots], but defended
/// levels get them too, outside every turret's view (a cache is a gamble,
/// not a trap) and clear of the reactor.
List<Pt> salvageSpots(LevelSpec spec, {ShipSpec ship = kKestrel}) =>
    _cache['salvage/${spec.id}/${ship.id}'] ??= _spots(spec, ship, defended: true);

final Map<String, List<Pt>> _cache = {};

/// A turret at [t] could see a ship at [p]: in range (+1 m), in its arc
/// (+0.2 rad) and with open cave between them.
bool turretMightSee(TurretSpec t, Pt p, bool Function(Pt a, Pt b) clearLine) {
  final dx = p.x - t.base.x, dy = p.y - t.base.y;
  if (dx * dx + dy * dy > (t.range + 1) * (t.range + 1)) return false;
  var off = (math.atan2(dy, dx) - t.facing) % (2 * math.pi);
  if (off > math.pi) off -= 2 * math.pi;
  if (off.abs() > t.aimArc + 0.2) return false;
  return clearLine(t.base, p);
}

List<Pt> _spots(LevelSpec spec, ShipSpec ship, {required bool defended}) {
  final hasDefences = spec.obstacles.any((o) => o is TurretSpec || o is ReactorSpec);
  if (hasDefences && !defended) return const [];
  final cave = buildCave(spec);
  final field = caveFieldWithCores(cave, spec);
  final nx = cave.nx;
  final ny = cave.ny;
  final cell = cave.cell;
  final stride = nx + 1;
  final clear = -(ship.circumradius + 0.04);
  final roomy = -(ship.circumradius + 0.6);

  int key(Pt p) =>
      (p.y / cell).round().clamp(0, ny) * stride + (p.x / cell).round().clamp(0, nx);

  // Flood from the spawn: parent links give shortest 8-connected paths.
  Int32List flood(Pt from) {
    final parent = Int32List(stride * (ny + 1))..fillRange(0, stride * (ny + 1), -2);
    final start = key(from);
    if (field[start] >= clear) return parent;
    parent[start] = -1;
    final q = Queue<int>()..add(start);
    while (q.isNotEmpty) {
      final k = q.removeFirst();
      final i = k % stride;
      final j = k ~/ stride;
      for (final (di, dj) in _dirs8) {
        final i2 = i + di;
        final j2 = j + dj;
        if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) continue;
        final k2 = j2 * stride + i2;
        if (parent[k2] != -2 || field[k2] >= clear) continue;
        if (di != 0 && dj != 0 &&
            (field[j * stride + i2] >= clear || field[j2 * stride + i] >= clear)) {
          continue;
        }
        parent[k2] = k;
        q.add(k2);
      }
    }
    return parent;
  }

  // Nearest reached node to [p] (anchors sit just outside the margin).
  int? reachedNear(Int32List parent, Pt p, double radius) {
    final r = (radius / cell).ceil();
    final pi = (p.x / cell).round();
    final pj = (p.y / cell).round();
    int? best;
    var bestD = 1 << 30;
    for (int dj = -r; dj <= r; dj++) {
      for (int di = -r; di <= r; di++) {
        final i = pi + di;
        final j = pj + dj;
        if (i < 0 || j < 0 || i > nx || j > ny) continue;
        final k = j * stride + i;
        if (parent[k] == -2) continue;
        final d = di * di + dj * dj;
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
    }
    return best;
  }

  List<Pt> pathTo(Int32List parent, int? end) {
    final out = <Pt>[];
    for (var c = end ?? -1; c >= 0; c = parent[c]) {
      out.add(Pt((c % stride) * cell, (c ~/ stride) * cell));
    }
    return out;
  }

  final fromSpawn = flood(spec.shipSpawn);
  final cargoNode = reachedNear(fromSpawn, spec.cargoSpawn, 1.2);
  if (cargoNode == null) return const [];
  final fromCargo = flood(Pt((cargoNode % stride) * cell, (cargoNode ~/ stride) * cell));
  final route = [
    ...pathTo(fromSpawn, cargoNode),
    ...pathTo(fromCargo, reachedNear(fromCargo, spec.goal.center, 1.0)),
  ];
  // Thin the route for the distance test.
  final routePts = <Pt>[for (var k = 0; k < route.length; k += 5) route[k]];

  // Open cave all along a→b (the dome itself sits in rock, so the first
  // metre is skipped).
  bool clearLine(Pt a, Pt b) {
    final d = _dist(a, b);
    final n = (d / cell).ceil();
    for (var k = 0; k <= n; k++) {
      final t = k / math.max(1, n);
      if (t * d < 1.0) continue;
      final x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t;
      if (field[key(Pt(x, y))] >= 0) return false;
    }
    return true;
  }

  // Every pod and pad (an Expedition has several).
  final anchors = spec.anchorPoints;
  bool nearAnchor(Pt p) => anchors.any((a) => _dist(a, p) < kCrateAnchorClearance);

  bool inSweep(Pt p) {
    for (final o in spec.obstacles) {
      switch (o) {
        case RotatingBarSpec s:
          if (_dist(s.center, p) < s.halfLength + s.thickness + 0.9) return true;
        case PendulumSpec s:
          if (_dist(s.pivot, p) < s.length + s.bobRadius + 0.9) return true;
        case SlidingBlockSpec s:
          if (_segDist(s.from, s.to, p) < math.max(s.halfW, s.halfH) + 0.9) return true;
        case TurretSpec t:
          if (!defended || turretMightSee(t, p, clearLine)) return true;
        case ReactorSpec r:
          if (!defended || _dist(r.center, p) < r.radius + 2.5) return true;
      }
    }
    for (final f in spec.fields) {
      if (f is GravityWellSpec && _dist(f.center, p) < f.coreRadius + 2.5) return true;
    }
    return false;
  }

  final preferred = <(Pt, double)>[];
  final fallback = <(Pt, double)>[];
  final step = (1.0 / cell).round();
  for (int j = step; j < ny; j += step) {
    for (int i = step; i < nx; i += step) {
      final k = j * stride + i;
      if (fromSpawn[k] == -2 || field[k] > roomy) continue;
      final p = Pt(i * cell, j * cell);
      if (nearAnchor(p) || inSweep(p)) continue;
      var dRoute = double.infinity;
      for (final q in routePts) {
        dRoute = math.min(dRoute, _dist(q, p));
      }
      final entry = (p, dRoute);
      if (dRoute >= kCrateRouteMin && dRoute <= kCrateRouteMax) {
        preferred.add(entry);
      } else {
        fallback.add(entry);
      }
    }
  }
  if (preferred.length >= 3) return [for (final (p, _) in preferred) p];
  fallback.sort((a, b) => a.$2.compareTo(b.$2));
  return [
    for (final (p, _) in preferred) p,
    for (final (p, _) in fallback.take(6 - preferred.length)) p,
  ];
}

double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

double _segDist(Pt a, Pt b, Pt p) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0 ? 0.0 : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
  return _dist(Pt(a.x + dx * t, a.y + dy * t), p);
}

const _dirs8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
