import 'dart:math' as math;
import 'dart:collection';
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Pure-Dart playability checks shared by `flutter test` and the authoring
/// preview tool. Empty result = level is provably completable geometry for
/// [ship] (the ship the level is actually flown with).
///
/// An Expedition is checked leg by leg ([LevelSpec.forLeg]): each haul must
/// pass every check on its own, starting from the previous leg's pad with a
/// full tank (a staging pad refuels). Issues name their leg.
List<String> validateCaveSpec(LevelSpec spec, {ShipSpec ship = kKestrel}) {
  if (!spec.isExpedition) return _validateHaul(spec, ship);
  return [
    for (var k = 0; k < spec.legs.length; k++)
      for (final issue in _validateHaul(spec.forLeg(k), ship)) 'leg ${k + 1}: $issue',
  ];
}

/// Per-leg flight estimates of an Expedition (one entry for a mission).
List<FlightReport?> analyzeLegs(LevelSpec spec, {ShipSpec ship = kKestrel}) => [
      for (var k = 0; k < spec.allLegs.length; k++)
        analyzeFlight(spec.isExpedition ? spec.forLeg(k) : spec, ship: ship),
    ];

List<String> _validateHaul(LevelSpec spec, ShipSpec ship) {
  final issues = <String>[];
  final cave = buildCave(spec);

  // Ship needs its hull circumradius (Kestrel 0.51) plus a small margin; the
  // main haul path must be comfortably wider.
  final shipClear = -(ship.circumradius + 0.04);

  // Well cores are solid rock for every geometric check.
  final field = caveFieldWithCores(cave, spec);
  double f(double x, double y) => math.max(cave.fieldAt(x, y), wellCoreField(spec, x, y));

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
  // A flat floor right under the pad (the builder's shelf), so a landed ship
  // and pod rest inside the win sensors instead of rolling off a slope.
  final floorY = padFloorY(g);
  for (int k = 0; k <= 6; k++) {
    final x = g.center.x - g.halfW + 0.3 + k * (2 * g.halfW - 0.6) / 6;
    var y = g.center.y;
    while (y < floorY + 1.0 && f(x, y) < 0) {
      y += 0.02;
    }
    if ((y - floorY).abs() > 0.1) {
      issues.add('pad not grounded at x ${x.toStringAsFixed(1)}: floor '
          '${(y - floorY).toStringAsFixed(2)} m off the pad floor');
      break;
    }
  }

  // 2. BFS reachability with ship clearance on the sampled grid.
  final nx = cave.nx;
  final ny = cave.ny;
  bool passable(int i, int j) => field[j * (nx + 1) + i] < shipClear;

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
  //    A locked pod (cargoClamped) stays exactly at its spawn.
  double? restY = spec.cargoClamped ? spec.cargoSpawn.y : null;
  for (double y = spec.cargoSpawn.y; restY == null && y < spec.cargoSpawn.y + 4.5; y += 0.05) {
    if (f(spec.cargoSpawn.x, y) >= 0) restY = y - kCargoRadius;
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

  // 5. Force fields: wind the ship can beat, and calm, "down" anchors.
  issues.addAll(_fieldIssues(spec, ship));

  // 6. Obstacle sweeps must not sit on the anchors.
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

  // 7. Defences and pickups.
  issues.addAll(_combatIssues(spec, ship, f));
  for (final p in spec.pickups) {
    if (f(p.pos.x, p.pos.y) > -0.6) {
      issues.add('PICKUP: (${p.pos.x},${p.pos.y}) is not in open space');
    } else if (reached != null && !reachedNear(reached, p.pos, 0.8)) {
      issues.add('PICKUP: (${p.pos.x},${p.pos.y}) cannot be reached');
    }
  }

  return issues;
}

/// Turrets sit on rock, face open space, and never see the spawn pad, the
/// cargo pocket or the goal pad — the anchors are always safe to sit on.
/// Turrets and reactors need an armed ship (an unarmed one can't fight back).
List<String> _combatIssues(
  LevelSpec spec,
  ShipSpec ship,
  double Function(double x, double y) f,
) {
  final issues = <String>[];
  // Rock along the segment (sampled every 0.1 m) blocks sight.
  bool clearSight(Pt a, Pt b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final n = math.max(1, (math.sqrt(dx * dx + dy * dy) / 0.1).ceil());
    for (var i = 1; i < n; i++) {
      if (f(a.x + dx * i / n, a.y + dy * i / n) >= 0) return false;
    }
    return true;
  }

  for (final o in spec.obstacles) {
    switch (o) {
      case TurretSpec t:
        final at = '(${t.base.x},${t.base.y})';
        if (!ship.armed) issues.add('TURRET: $at but ${ship.name} is unarmed');
        final onWall = f(t.base.x, t.base.y);
        if (onWall < -0.45 || onWall > 0.35) {
          issues.add('TURRET: $at is not on a wall '
              '(field ${onWall.toStringAsFixed(2)}, need -0.45..0.35)');
        }
        // Muzzle point (dome 0.5 m + barrel 0.6 m, see Turret).
        final out = Pt(t.base.x + math.cos(t.facing) * 1.1, t.base.y + math.sin(t.facing) * 1.1);
        if (f(out.x, out.y) > -0.3) {
          issues.add('TURRET: $at faces into rock');
        }
        for (final (label, p) in [
          ('ship spawn', spec.shipSpawn),
          ('cargo', spec.cargoSpawn),
          ('goal', spec.goal.center),
        ]) {
          final dx = p.x - out.x;
          final dy = p.y - out.y;
          final dist = math.sqrt(dx * dx + dy * dy);
          var off = (math.atan2(dy, dx) - t.facing) % (2 * math.pi);
          if (off > math.pi) off -= 2 * math.pi;
          if (dist <= t.range + 0.5 && off.abs() <= t.aimArc + 0.1 && clearSight(out, p)) {
            issues.add('TURRET: $at can see the $label');
          }
        }
      case ReactorSpec r:
        if (!ship.armed) {
          issues.add('REACTOR: at (${r.center.x},${r.center.y}) but ${ship.name} is unarmed');
        }
        if (f(r.center.x, r.center.y) > -(r.radius + 0.5)) {
          issues.add('REACTOR: (${r.center.x},${r.center.y}) needs open space around it');
        }
      case RotatingBarSpec() || PendulumSpec() || SlidingBlockSpec():
        break;
    }
  }
  return issues;
}

/// Wind may be at most this fraction of the loaded ship's thrust accel, and
/// never gust past [kMaxWindG] — stronger reads as random shoving, not skill.
const double kMaxWindFraction = 0.45;
const double kMaxWindG = 1.0;

/// At spawn, cargo and goal the local pull must point within this angle of
/// straight down and be at least [kMinAnchorGravity] × base strength — or be
/// near-weightless (≤ [kMaxDriftGravity], you just drift). A locked cargo pod
/// (`cargoClamped`) is exempt: it can't move until hooked.
const double kMaxAnchorTiltDeg = 25;
const double kMinAnchorGravity = 0.3;
const double kMaxDriftGravity = 0.2;

/// Well cores must keep this much open space (m) from spawn, cargo and goal.
const double kWellCoreClearance = 1.5;

List<String> _fieldIssues(LevelSpec spec, ShipSpec ship) {
  if (spec.fields.isEmpty) return const [];
  final issues = <String>[];
  for (final w in spec.fields.whereType<GravityWellSpec>()) {
    for (final (label, p) in [
      ('ship spawn', spec.shipSpawn),
      ('cargo', spec.cargoSpawn),
      ('goal', spec.goal.center),
    ]) {
      final gap = math.sqrt(math.pow(p.x - w.center.x, 2) + math.pow(p.y - w.center.y, 2)) -
          w.coreRadius;
      if (gap < kWellCoreClearance) {
        issues.add('WELL: core at (${w.center.x},${w.center.y}) is '
            '${gap.toStringAsFixed(1)} m from $label (min $kWellCoreClearance)');
      }
    }
  }
  final cargoMass = math.pi * kCargoRadius * kCargoRadius * kCargoDensity *
      spec.modifiers.cargoDensityMul;
  final aLoaded = ship.thrustForce / (ship.mass + cargoMass);

  var maxPeriod = 1.0;
  for (final f in spec.fields) {
    if (f is WindZoneSpec) {
      final peakG = math.sqrt(f.ax * f.ax + f.ay * f.ay) * (1 + f.gustAmp.abs());
      final peak = peakG * kGravityY;
      if (peakG > kMaxWindG) {
        issues.add('WIND: zone at (${f.center.x},${f.center.y}) gusts to '
            '${peakG.toStringAsFixed(2)}g (max ${kMaxWindG}g)');
      } else if (peak > kMaxWindFraction * aLoaded) {
        issues.add('WIND: zone at (${f.center.x},${f.center.y}) peaks at '
            '${(peak / aLoaded * 100).round()}% of thrust '
            '(max ${(kMaxWindFraction * 100).round()}%)');
      }
      maxPeriod = math.max(maxPeriod, f.gustPeriod);
    }
  }

  final sampler = FieldSampler(
    fields: spec.fields,
    g0: kGravityY,
    gravityMul: spec.modifiers.gravityMul,
  );
  final minG = kMinAnchorGravity * kGravityY;
  final maxTilt = kMaxAnchorTiltDeg * math.pi / 180;
  for (final (label, p) in [
    ('ship spawn', spec.shipSpawn),
    ('cargo', spec.cargoSpawn),
    ('goal', spec.goal.center),
  ]) {
    // Sample a full gust cycle so a peak gust can't upset an anchor.
    for (var i = 0; i < 16; i++) {
      final a = sampler.accelAt(p.x, p.y, t: maxPeriod * i / 16, cargo: label == 'cargo');
      final mag = math.sqrt(a.x * a.x + a.y * a.y);
      final tilt = mag < 1e-9 ? math.pi : math.acos((a.y / mag).clamp(-1.0, 1.0));
      final calmDown = mag >= minG && tilt <= maxTilt;
      final drifting = mag <= kMaxDriftGravity * kGravityY;
      final locked = label == 'cargo' && spec.cargoClamped;
      if (!calmDown && !drifting && !locked) {
        issues.add('FIELD: $label is not calm '
            '(pull ${(mag / kGravityY).toStringAsFixed(2)}g, '
            'tilt ${(tilt * 180 / math.pi).round()}°)');
        break;
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
    case TurretSpec s:
      // The dome plus barrel reach (static — shells are checked separately).
      const r = 1.2;
      return (s.base.x - r, s.base.y - r, s.base.x + r, s.base.y + r);
    case ReactorSpec s:
      return (
        s.center.x - s.radius,
        s.center.y - s.radius,
        s.center.x + s.radius,
        s.center.y + s.radius,
      );
  }
}

/// Coarse ASCII picture of the carved cave for terminal authoring.
/// `#` rock, `.` open, `S` ship, `c` cargo, `G` goal, `!` obstacle center,
/// `~` wind, `z` gravity zone, `0` zero-g zone, `o` gravity well,
/// `T` turret, `R` reactor, `F` fuel canister; an Expedition numbers its
/// pods `1 2 3…` and pads `A B C…`.
String asciiPreview(LevelSpec spec, {double res = 0.5}) {
  final cave = buildCave(spec);
  final cols = (spec.worldW / res).ceil();
  final rows = (spec.worldH / res).ceil();
  final grid =
      List.generate(rows, (_) => List.filled(cols, ' '), growable: false);
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      final x = (c + 0.5) * res;
      final y = (r + 0.5) * res;
      grid[r][c] = math.max(cave.fieldAt(x, y), wellCoreField(spec, x, y)) < 0 ? '.' : '#';
    }
  }
  void mark(Pt p, String ch) {
    final r = (p.y / res).floor().clamp(0, rows - 1);
    final c = (p.x / res).floor().clamp(0, cols - 1);
    grid[r][c] = ch;
  }

  // Fields over open cells: `~` wind, `z` gravity zone (`0` if zero-g),
  // `o` well center. Zones are drawn by bounding box.
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      if (grid[r][c] != '.') continue;
      final x = (c + 0.5) * res;
      final y = (r + 0.5) * res;
      for (final f in spec.fields) {
        final inside = switch (f) {
          WindZoneSpec() => (x - f.center.x).abs() < f.halfW && (y - f.center.y).abs() < f.halfH,
          GravityZoneSpec() => (x - f.center.x).abs() < f.halfW && (y - f.center.y).abs() < f.halfH,
          GravityWellSpec() => false,
        };
        if (!inside) continue;
        grid[r][c] = switch (f) {
          WindZoneSpec() => '~',
          GravityZoneSpec() => (f.gx * f.gx + f.gy * f.gy) < 0.0025 ? '0' : 'z',
          GravityWellSpec() => 'o',
        };
      }
    }
  }
  for (final f in spec.fields) {
    if (f is GravityWellSpec) mark(f.center, 'o');
  }
  for (final o in spec.obstacles) {
    switch (o) {
      case TurretSpec t:
        mark(t.base, 'T');
      case ReactorSpec r:
        mark(r.center, 'R');
      default:
        final aabb = _obstacleSweepAabb(o);
        mark(Pt((aabb.$1 + aabb.$3) / 2, (aabb.$2 + aabb.$4) / 2), '!');
    }
  }
  for (final p in spec.pickups) {
    mark(p.pos, 'F');
  }
  mark(spec.shipSpawn, 'S');
  if (spec.isExpedition) {
    // Legs numbered: pod `1` goes to pad `A`, pod `2` to pad `B`, …
    for (final (k, l) in spec.legs.indexed) {
      mark(l.cargoSpawn, '${k + 1}');
      mark(l.goal.center, String.fromCharCode(0x41 + k));
    }
  } else {
    mark(spec.cargoSpawn, 'c');
    mark(spec.goal.center, 'G');
  }
  return grid.map((row) => row.join()).join('\n');
}


// ── Flight physics heuristics ──────────────────────────────────────────────

/// Thrust must beat the strongest pull on the route (ship + cargo, heaviest
/// daily-challenge gravity) by this factor — below it, flying feels sluggish.
const double kMinLiftRatio = 2.0;

/// Estimated burn for a clean run must leave a comfortable reserve.
const double kMaxFuelFraction = 0.6;

/// A fuel canister this close to the estimated route counts as collected
/// on the way (`FuelCell.pickupRadius` plus a little steering).
const double kOnRoutePickupRadius = 1.2;

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
    this.towRoute = const [],
  });

  /// Meters flown spawn → cargo → goal along the shortest clear route.
  final double pathLength;

  /// Thrust acceleration (with cargo) ÷ strongest pull on the route.
  final double liftRatio;

  /// Estimated fraction of the tank burned on a clean run, net of fuel
  /// canisters picked up along the route.
  final double fuelFraction;

  /// Strongest local acceleration on the route (m/s², release gravity).
  final double maxPull;

  /// The loaded leg (cargo pickup → goal) as clear points in meters; used to
  /// pose the ship for store screenshots.
  final List<Pt> towRoute;

  @override
  String toString() => 'path ${pathLength.toStringAsFixed(1)} m, '
      'lift ×${liftRatio.toStringAsFixed(1)}, '
      'fuel ~${(fuelFraction * 100).round()}%, '
      'max pull ${maxPull.toStringAsFixed(2)} m/s²';
}

/// Impulse-based flight estimate. Holding a steady course against a pull `a`
/// needs thrust impulse `m·|a|·t` no matter how the pilot flies it, so the
/// fuel floor is ∫|a + drag|/a_thrust dt along the route at cruise speed,
/// scaled by an overhead for turns and corrections. Null if no route exists.
FlightReport? analyzeFlight(LevelSpec spec, {ShipSpec ship = kKestrel}) {
  final cave = buildCave(spec);
  final nx = cave.nx;
  final ny = cave.ny;
  final stride = nx + 1;
  final clear = -(ship.circumradius + 0.04);
  final field = caveFieldWithCores(cave, spec);

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
    if (field[start] >= clear) return null;
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
        if (parent[k2] != -2 || field[k2] >= clear) continue;
        if (di != 0 && dj != 0 &&
            (field[j * stride + i2] >= clear || field[j2 * stride + i] >= clear)) {
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
  // Canisters on the route refill what has been burned so far (the tank
  // caps the rest), in burn-seconds.
  final drainPerSec = ship.fuelDrainPerSecond * spec.modifiers.fuelDrainMul;
  final pending = [
    for (final p in spec.pickups)
      if (p is FuelCellSpec) p,
  ];
  var credit = 0.0;
  for (final (path, aThrust) in [(toCargo, aEmpty), (toGoal, aLoaded)]) {
    for (var n = 1; n < path.length; n++) {
      final k = path[n];
      final px = (k % stride) * cave.cell;
      final py = (k ~/ stride) * cave.cell;
      pending.removeWhere((c) {
        final dx = c.pos.x - px;
        final dy = c.pos.y - py;
        if (dx * dx + dy * dy > kOnRoutePickupRadius * kOnRoutePickupRadius) return false;
        final used = burn * _maneuverOverhead - credit;
        credit += math.min(c.amount / drainPerSec, math.max(0.0, used));
        return true;
      });
      final diagonal = (k % stride) != (path[n - 1] % stride) &&
          (k ~/ stride) != (path[n - 1] ~/ stride);
      final ds = diagonal ? cave.cell * math.sqrt2 : cave.cell;
      final a = sampler.accelAt((k % stride) * cave.cell, (k ~/ stride) * cave.cell);
      final pull = math.sqrt(a.x * a.x + a.y * a.y);
      maxPull = math.max(maxPull, pull);
      // Holding cruise speed also fights the hull's linear drag (c·v), which
      // is what costs fuel in zero-g.
      final drag = ship.linearDamping * _cruiseSpeed;
      burn += math.sqrt(pull * pull + drag * drag) / aThrust * ds / _cruiseSpeed;
      length += ds;
    }
  }

  // Lift at the heaviest daily gravity (clamped like the runtime does).
  final worstMul = combinedGravityMul(spec.modifiers.gravityMul, kMaxChallengeGravityMul) /
      math.max(spec.modifiers.gravityMul, 1e-9);
  final worstPull = spec.modifiers.gravityMul == 0
      ? maxPull * kMaxChallengeGravityMul
      : maxPull * math.max(worstMul, 1.0);
  final liftRatio = worstPull <= 1e-9 ? double.infinity : aLoaded / worstPull;

  final burnSeconds = ship.burnSeconds / spec.modifiers.fuelDrainMul;
  return FlightReport(
    pathLength: length,
    liftRatio: liftRatio,
    fuelFraction: (burn * _maneuverOverhead - credit) / burnSeconds,
    maxPull: maxPull,
    towRoute: [
      for (final k in toGoal) Pt((k % stride) * cave.cell, (k ~/ stride) * cave.cell),
    ],
  );
}

const _dirs8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

