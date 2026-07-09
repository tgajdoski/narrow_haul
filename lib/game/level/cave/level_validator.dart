import 'dart:math' as math;
import 'dart:collection';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// Pure-Dart playability checks shared by `flutter test` and the authoring
/// preview tool. Empty result = level is provably completable geometry.
List<String> validateCaveSpec(LevelSpec spec) {
  final issues = <String>[];
  final cave = buildCave(spec);

  // Ship needs ~0.42 m clearance (triangle circumradius 0.51, half-width
  // 0.315); the main haul path must be comfortably wider.
  const shipClear = -0.55;

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

  // 4. Obstacle sweeps must not sit on the anchors.
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
