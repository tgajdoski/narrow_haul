import 'dart:math' as math;
import 'dart:collection';
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Pure-Dart playability checks shared by `flutter test` and the authoring
/// preview tool. Empty result = level is provably completable geometry for
/// [ship] (the ship the level is actually flown with).
List<String> validateCaveSpec(LevelSpec spec, {ShipSpec ship = kKestrel}) {
  final issues = <String>[];
  final cave = buildCave(spec);

  // Ship needs its hull circumradius (Kestrel 0.51) plus a small margin; the
  // main haul path must be comfortably wider.
  final shipClear = -(ship.circumradius + 0.04);

  double f(double x, double y) => cave.fieldAt(x, y);

  // 1. Anchor openness — calm pockets around pads and cargo.
  if (f(spec.shipSpawn.x, spec.shipSpawn.y) > -1.0) {
    issues.add('ship spawn not in an open pocket '
        '(field ${f(spec.shipSpawn.x, spec.shipSpawn.y).toStringAsFixed(2)}, need < -1.0)');
  }
  if (f(spec.cargoSpawn.x, spec.cargoSpawn.y) > -0.5) {
    issues.add('cargo spawn not open '
        '(field ${f(spec.cargoSpawn.x, spec.cargoSpawn.y).toStringAsFixed(2)}, need < -0.5)');
  }
  final g = spec.goal;
  if (f(g.center.x, g.center.y) > -0.8) {
    issues.add('goal center not open '
        '(field ${f(g.center.x, g.center.y).toStringAsFixed(2)}, need < -0.8)');
  }
  for (final corner in [
    Pt(g.center.x - g.halfW, g.center.y - g.halfH),
    Pt(g.center.x + g.halfW, g.center.y - g.halfH),
  ]) {
    if (f(corner.x, corner.y) > -0.35) {
      issues.add('goal top corner (${corner.x.toStringAsFixed(1)},'
          '${corner.y.toStringAsFixed(1)}) blocked — pad must be fully open');
    }
  }
  // Approach clearance above the pad (win sensor needs the ship inside).
  if (f(g.center.x, g.center.y - g.halfH - 0.7) > -0.42) {
    issues.add('no approach clearance above goal pad');
  }

  // 2. BFS reachability with ship clearance on the sampled grid.
  final nx = cave.nx;
  final ny = cave.ny;
  bool passable(int i, int j) => cave.field[j * (nx + 1) + i] < shipClear;

  (int, int) cellOf(Pt p) => (
        (p.x / cave.cell).round().clamp(0, nx),
        (p.y / cave.cell).round().clamp(0, ny),
      );

  Set<int>? reached;
  Set<int> bfs((int, int) start) {
    final seen = <int>{};
    if (!passable(start.$1, start.$2)) return seen;
    final q = Queue<(int, int)>()..add(start);
    seen.add(start.$2 * (nx + 1) + start.$1);
    while (q.isNotEmpty) {
      final (ci, cj) = q.removeFirst();
      for (final (di, dj) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final i2 = ci + di;
        final j2 = cj + dj;
        if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) continue;
        final key = j2 * (nx + 1) + i2;
        if (seen.contains(key) || !passable(i2, j2)) continue;
        seen.add(key);
        q.add((i2, j2));
      }
    }
    return seen;
  }

  bool reachedNear(Set<int> seen, Pt p, double radius) {
    final r = (radius / cave.cell).ceil();
    final (pi, pj) = cellOf(p);
    for (int dj = -r; dj <= r; dj++) {
      for (int di = -r; di <= r; di++) {
        if (di * di + dj * dj > r * r) continue;
        final i2 = pi + di;
        final j2 = pj + dj;
        if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) continue;
        if (seen.contains(j2 * (nx + 1) + i2)) return true;
      }
    }
    return false;
  }

  final shipCell = cellOf(spec.shipSpawn);
  if (!passable(shipCell.$1, shipCell.$2)) {
    issues.add('ship spawn cell blocked at clearance threshold');
  } else {
    reached = bfs(shipCell);
    if (!reachedNear(reached, spec.cargoSpawn, 1.0)) {
      issues.add('UNREACHABLE: cargo cannot be approached from ship spawn');
    }
    if (!reachedNear(reached, g.center, 0.8)) {
      issues.add('UNREACHABLE: goal cannot be reached from ship spawn');
    }
  }

  // 3. Cargo must come to rest close below its spawn, and the rest point
  //    must be approachable (auto-attach needs the ship within ~1.2 m).
  double? restY;
  for (double y = spec.cargoSpawn.y; y < spec.cargoSpawn.y + 4.5; y += 0.05) {
    if (f(spec.cargoSpawn.x, y) >= 0) {
      restY = y - 0.15;
      break;
    }
  }
  if (restY == null) {
    issues.add('cargo has no floor within 4.5 m below spawn');
  } else if (reached != null &&
      !reachedNear(reached, Pt(spec.cargoSpawn.x, restY), 1.15)) {
    issues.add('cargo rest point not approachable within attach range');
  }

  // 4. Flight physics: lift margin and fuel budget along the haul path.
  if (reached != null && restY != null) {
    final flight = analyzeFlight(spec, ship: ship);
    if (flight == null) {
      issues.add('no flight path found for physics checks');
    } else {
      if (flight.liftRatio < kMinLiftRatio) {
        issues.add('LIFT: thrust/pull ratio ${flight.liftRatio.toStringAsFixed(2)} '
            '< $kMinLiftRatio with cargo at heaviest daily gravity');
      }
      if (flight.fuelFraction > kMaxFuelFraction) {
        issues.add('FUEL: estimated burn ${(flight.fuelFraction * 100).round()}% '
            'of tank > ${(kMaxFuelFraction * 100).round()}%');
      }
    }
  }

  // 5. Obstacle sweeps must not sit on the anchors.
  for (final o in spec.obstacles) {
    final sweep = _obstacleSweepAabb(o);
    for (final (label, p) in [
      ('ship spawn', spec.shipSpawn),
      ('goal', g.center),
    ]) {
      if (p.x >= sweep.$1 - 0.6 &&
          p.x <= sweep.$3 + 0.6 &&
          p.y >= sweep.$2 - 0.6 &&
          p.y <= sweep.$4 + 0.6) {
        issues.add('obstacle sweep overlaps $label');
      }
    }
  }

  return issues;
}

/// (minX, minY, maxX, maxY) swept by the obstacle over a full cycle.
(double, double, double, double) _obstacleSweepAabb(ObstacleSpec o) {
  switch (o) {
    case RotatingBarSpec s:
      final r = s.halfLength + s.thickness;
      return (s.center.x - r, s.center.y - r, s.center.x + r, s.center.y + r);
    case PendulumSpec s:
      final reach = s.length + s.bobRadius;
      final xSpan = s.length * math.sin(s.amplitudeRad) + s.bobRadius;
      return (
        s.pivot.x - xSpan,
        s.pivot.y - s.bobRadius,
        s.pivot.x + xSpan,
        s.pivot.y + reach
      );
    case SlidingBlockSpec s:
      return (
        math.min(s.from.x, s.to.x) - s.halfW,
        math.min(s.from.y, s.to.y) - s.halfH,
        math.max(s.from.x, s.to.x) + s.halfW,
        math.max(s.from.y, s.to.y) + s.halfH,
      );
  }
}

/// Coarse ASCII picture of the carved cave for terminal authoring.
/// `#` rock, `.` open, `S` ship, `c` cargo, `G` goal, `!` obstacle center.
String asciiPreview(LevelSpec spec, {double res = 0.5}) {
  final cave = buildCave(spec);
  final cols = (spec.worldW / res).ceil();
  final rows = (spec.worldH / res).ceil();
  final grid =
      List.generate(rows, (_) => List.filled(cols, ' '), growable: false);
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      grid[r][c] = cave.fieldAt((c + 0.5) * res, (r + 0.5) * res) < 0 ? '.' : '#';
    }
  }
  void mark(Pt p, String ch) {
    final r = (p.y / res).floor().clamp(0, rows - 1);
    final c = (p.x / res).floor().clamp(0, cols - 1);
    grid[r][c] = ch;
  }

  for (final o in spec.obstacles) {
    final aabb = _obstacleSweepAabb(o);
    mark(Pt((aabb.$1 + aabb.$3) / 2, (aabb.$2 + aabb.$4) / 2), '!');
  }
  mark(spec.shipSpawn, 'S');
  mark(spec.cargoSpawn, 'c');
  mark(spec.goal.center, 'G');
  return grid.map((row) => row.join()).join('\n');
}


// ── Flight physics heuristics ──────────────────────────────────────────────

/// Thrust must beat the strongest pull on the route (ship + cargo, heaviest
/// daily-challenge gravity) by this factor — below it, flying feels sluggish.
const double kMinLiftRatio = 2.0;

/// Estimated burn for a clean run must leave a comfortable reserve.
const double kMaxFuelFraction = 0.6;

/// Assumed average cruise speed (m/s) and a maneuvering overhead on top of the
/// impulse floor. Calibrated so existing hand-tuned levels sit well inside.
const double _cruiseSpeed = 2.5;
const double _maneuverOverhead = 1.3;

class FlightReport {
  const FlightReport({
    required this.pathLength,
    required this.liftRatio,
    required this.fuelFraction,
    required this.maxPull,
  });

  /// Meters flown spawn → cargo → goal along the shortest clear route.
  final double pathLength;

  /// Thrust acceleration (with cargo) ÷ strongest pull on the route.
  final double liftRatio;

  /// Estimated fraction of the tank burned on a clean run.
  final double fuelFraction;

  /// Strongest local acceleration on the route (m/s², release gravity).
  final double maxPull;

  @override
  String toString() => 'path ${pathLength.toStringAsFixed(1)} m, '
      'lift ×${liftRatio.toStringAsFixed(1)}, '
      'fuel ~${(fuelFraction * 100).round()}%, '
      'max pull ${maxPull.toStringAsFixed(2)} m/s²';
}

/// Impulse-based flight estimate. Holding a steady course against a pull `a`
/// needs thrust impulse `m·|a|·t` no matter how the pilot flies it, so the
/// fuel floor is ∫|a|/a_thrust dt along the route at cruise speed, scaled by
/// an overhead for turns and corrections. Null if no route exists.
FlightReport? analyzeFlight(LevelSpec spec, {ShipSpec ship = kKestrel}) {
  final cave = buildCave(spec);
  final nx = cave.nx;
  final ny = cave.ny;
  final stride = nx + 1;
  final clear = -(ship.circumradius + 0.04);

  final sampler = FieldSampler(
    fields: spec.fields,
    g0: kGravityY,
    gravityMul: spec.modifiers.gravityMul,
  );

  int key(Pt p) =>
      (p.y / cave.cell).round().clamp(0, ny) * stride +
      (p.x / cave.cell).round().clamp(0, nx);

  // Fewest-step 8-connected route over clear cells (no corner cutting);
  // null if [to] is unreachable.
  List<int>? route(Pt from, Pt to, double tolerance) {
    final parent = Int32List(stride * (ny + 1))..fillRange(0, stride * (ny + 1), -2);
    final start = key(from);
    if (cave.field[start] >= clear) return null;
    final tc = (to.x / cave.cell, to.y / cave.cell);
    final tol = tolerance / cave.cell;
    parent[start] = -1;
    final q = Queue<int>()..add(start);
    while (q.isNotEmpty) {
      final k = q.removeFirst();
      final i = k % stride;
      final j = k ~/ stride;
      final dx = i - tc.$1;
      final dy = j - tc.$2;
      if (dx * dx + dy * dy <= tol * tol) {
        final path = <int>[];
        for (var c = k; c != -1; c = parent[c]) {
          path.add(c);
        }
        return path.reversed.toList();
      }
      for (final (di, dj) in _dirs8) {
        final i2 = i + di;
        final j2 = j + dj;
        if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) continue;
        final k2 = j2 * stride + i2;
        if (parent[k2] != -2 || cave.field[k2] >= clear) continue;
        if (di != 0 && dj != 0 &&
            (cave.field[j * stride + i2] >= clear || cave.field[j2 * stride + i] >= clear)) {
          continue;
        }
        parent[k2] = k;
        q.add(k2);
      }
    }
    return null;
  }

  final toCargo = route(spec.shipSpawn, spec.cargoSpawn, 1.15);
  if (toCargo == null) return null;
  final last = toCargo.last;
  final pickup = Pt((last % stride) * cave.cell, (last ~/ stride) * cave.cell);
  final toGoal = route(pickup, spec.goal.center, 0.8);
  if (toGoal == null) return null;

  final cargoMass =
      math.pi * kCargoRadius * kCargoRadius * kCargoDensity * spec.modifiers.cargoDensityMul;
  final aEmpty = ship.thrustForce / ship.mass;
  final aLoaded = ship.thrustForce / (ship.mass + cargoMass);
  var burn = 0.0; // seconds of full thrust
  var maxPull = 0.0;
  var length = 0.0;
  for (final (path, aThrust) in [(toCargo, aEmpty), (toGoal, aLoaded)]) {
    for (var n = 1; n < path.length; n++) {
      final k = path[n];
      final diagonal = (k % stride) != (path[n - 1] % stride) &&
          (k ~/ stride) != (path[n - 1] ~/ stride);
      final ds = diagonal ? cave.cell * math.sqrt2 : cave.cell;
      final a = sampler.accelAt((k % stride) * cave.cell, (k ~/ stride) * cave.cell);
      final pull = math.sqrt(a.x * a.x + a.y * a.y);
      maxPull = math.max(maxPull, pull);
      burn += pull / aThrust * ds / _cruiseSpeed;
      length += ds;
    }
  }

  // Lift at the heaviest daily gravity (clamped like the runtime does).
  final worstMul = math.min(kMaxChallengeGravityMul * spec.modifiers.gravityMul, kMaxGravityMul) /
      math.max(spec.modifiers.gravityMul, 1e-9);
  final worstPull = spec.modifiers.gravityMul == 0
      ? maxPull * kMaxChallengeGravityMul
      : maxPull * math.max(worstMul, 1.0);
  final liftRatio = worstPull <= 1e-9 ? double.infinity : aLoaded / worstPull;

  final burnSeconds = ship.burnSeconds / spec.modifiers.fuelDrainMul;
  return FlightReport(
    pathLength: length,
    liftRatio: liftRatio,
    fuelFraction: burn * _maneuverOverhead / burnSeconds,
    maxPull: maxPull,
  );
}

const _dirs8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
