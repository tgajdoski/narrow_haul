import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/physics_core.dart';

/// Result of carving a [LevelSpec] into geometry. Pure data — no Flame/dart:ui
/// so tests can run it headless.
class BuiltCave {
  BuiltCave({
    required this.loops,
    required this.cell,
    required this.nx,
    required this.ny,
    required this.field,
    required this.worldW,
    required this.worldH,
  });

  /// Closed rock/air boundary loops in meters (physics + render).
  final List<List<Pt>> loops;

  final double cell;
  final int nx;
  final int ny;

  /// Sampled signed field, row-major (nx+1)×(ny+1). Negative = open cave.
  final Float32List field;
  final double worldW;
  final double worldH;

  /// Bilinear field lookup at a world position. Positive (solid) outside grid.
  double fieldAt(double x, double y) {
    final fx = x / cell;
    final fy = y / cell;
    final ix = fx.floor();
    final iy = fy.floor();
    if (ix < 0 || iy < 0 || ix >= nx || iy >= ny) return 10;
    final u = fx - ix;
    final v = fy - iy;
    final a = field[iy * (nx + 1) + ix];
    final b = field[iy * (nx + 1) + ix + 1];
    final c = field[(iy + 1) * (nx + 1) + ix];
    final d = field[(iy + 1) * (nx + 1) + ix + 1];
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }
}

/// Memoized per level id — restart rebuilds nothing. Cleared for hot reload.
final Map<String, BuiltCave> _cache = {};

void clearCaveCache() => _cache.clear();

BuiltCave buildCave(LevelSpec spec) => _cache[spec.id] ??= _build(spec);

/// Builds [spec] on a background isolate (unless cached) and caches it, so
/// the following [buildCave] is instant and a level load doesn't freeze the
/// UI for the 50–300 ms a build takes on a phone.
Future<void> prebuildCave(LevelSpec spec) async {
  if (_cache.containsKey(spec.id)) return;
  final built = await Isolate.run(() => _build(spec));
  _cache[spec.id] ??= built;
}

const double _solid = 10.0;
const double _sminK = 1.0;

class _Capsule {
  _Capsule(this.ax, this.ay, this.bx, this.by, this.ra, this.rb);
  final double ax, ay, bx, by, ra, rb;
}

class _Ellipse {
  _Ellipse(this.cx, this.cy, this.rx, this.ry);
  final double cx, cy, rx, ry;
}

BuiltCave _build(LevelSpec spec) {
  const cell = 0.1;
  final nx = (spec.worldW / cell).ceil();
  final ny = (spec.worldH / cell).ceil();

  // 1. Tessellate tunnels into capsule primitives; collect chambers.
  final capsules = <_Capsule>[];
  for (final t in spec.tunnels) {
    final (pts, radii) = tessellateCatmullRom(t.points, t.radii);
    for (int i = 0; i < pts.length - 1; i++) {
      capsules.add(_Capsule(
        pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, radii[i], radii[i + 1]));
    }
  }
  final ellipses =
      spec.chambers.map((c) => _Ellipse(c.center.x, c.center.y, c.rx, c.ry)).toList();

  // 2. Spatial hash of primitives (coarse 2 m bins) so each sample only
  //    evaluates nearby primitives. AABBs inflated by radius + smin window
  //    + noise amplitude so smin blending stays smooth at bin borders.
  const binSize = 2.0;
  final binsX = (spec.worldW / binSize).ceil() + 1;
  final binsY = (spec.worldH / binSize).ceil() + 1;
  final inflate = _sminK + spec.noise.amplitude + 0.3;
  final capBins = List<List<int>>.generate(binsX * binsY, (_) => <int>[]);
  final ellBins = List<List<int>>.generate(binsX * binsY, (_) => <int>[]);

  void binAabb(List<List<int>> bins, int idx, double x0, double y0, double x1, double y1) {
    final bx0 = math.max((x0 / binSize).floor(), 0);
    final by0 = math.max((y0 / binSize).floor(), 0);
    final bx1 = math.min((x1 / binSize).floor(), binsX - 1);
    final by1 = math.min((y1 / binSize).floor(), binsY - 1);
    for (int by = by0; by <= by1; by++) {
      for (int bx = bx0; bx <= bx1; bx++) {
        bins[by * binsX + bx].add(idx);
      }
    }
  }

  for (int i = 0; i < capsules.length; i++) {
    final c = capsules[i];
    final r = math.max(c.ra, c.rb) + inflate;
    binAabb(capBins, i, math.min(c.ax, c.bx) - r, math.min(c.ay, c.by) - r,
        math.max(c.ax, c.bx) + r, math.max(c.ay, c.by) + r);
  }
  for (int i = 0; i < ellipses.length; i++) {
    final e = ellipses[i];
    binAabb(ellBins, i, e.cx - e.rx - inflate, e.cy - e.ry - inflate,
        e.cx + e.rx + inflate, e.cy + e.ry + inflate);
  }

  // Anchors where boundary noise fades out to keep pads/spawns calm.
  final anchors = <Pt>[
    spec.shipSpawn,
    spec.cargoSpawn,
    spec.goal.center,
    Pt(spec.goal.center.x - spec.goal.halfW, spec.goal.center.y),
    Pt(spec.goal.center.x + spec.goal.halfW, spec.goal.center.y),
  ];

  // 3. Sample the field. Border samples are forced solid so every contour
  //    closes inside the grid.
  final field = Float32List((nx + 1) * (ny + 1));
  for (int j = 0; j <= ny; j++) {
    final y = j * cell;
    final rowSolid = j == 0 || j == ny;
    for (int i = 0; i <= nx; i++) {
      final idx = j * (nx + 1) + i;
      if (rowSolid || i == 0 || i == nx) {
        field[idx] = _solid;
        continue;
      }
      final x = i * cell;
      final bin = (y / binSize).floor() * binsX + (x / binSize).floor();

      double f = _solid;
      for (final ci in capBins[bin]) {
        final c = capsules[ci];
        f = smin(f, sdCapsule(x, y, c.ax, c.ay, c.bx, c.by, c.ra, c.rb), _sminK);
      }
      for (final ei in ellBins[bin]) {
        final e = ellipses[ei];
        f = smin(f, sdEllipseApprox(x, y, e.cx, e.cy, e.rx, e.ry), _sminK);
      }

      // Organic boundary roughness — only near the boundary, faded near
      // anchors, seeded by the spec (deterministic).
      if (f.abs() < 1.5) {
        double anchorDist = double.infinity;
        for (final a in anchors) {
          final dx = x - a.x;
          final dy = y - a.y;
          final d = dx * dx + dy * dy;
          if (d < anchorDist) anchorDist = d;
        }
        final fade = smoothstep(2.0, 4.0, math.sqrt(anchorDist));
        if (fade > 0) {
          f += spec.noise.amplitude *
              fade *
              fbm2(x * spec.noise.frequency, y * spec.noise.frequency, spec.seed,
                  octaves: spec.noise.octaves);
        }
      }
      field[idx] = f;
    }
  }

  _layPadShelf(field, nx, ny, cell, spec.goal);

  // 4–5. Contours → smoothed, simplified loops.
  final cleaned = extractCaveLoops(field, nx, ny, cell);

  return BuiltCave(
    loops: cleaned,
    cell: cell,
    nx: nx,
    ny: ny,
    field: field,
    worldW: spec.worldW,
    worldH: spec.worldH,
  );
}

/// Depth of the rock shelf under the delivery pad (m).
const double _padShelfDepth = 1.5;

/// Every delivery pad gets a flat floor: open air from the top of the pad box
/// down to [kPadFloorDrop] below it, then [_padShelfDepth] of rock a little
/// wider than the pad. A tunnel's slope or bowl under the pad would otherwise
/// leave the landed ship and pod outside the win sensors.
void _layPadShelf(Float32List field, int nx, int ny, double cell, GoalSpec g) {
  final floorY = padFloorY(g);
  final shelfHalfW = g.halfW + 0.4;
  final topY = g.center.y - g.halfH;
  final i0 = math.max(1, ((g.center.x - shelfHalfW - 0.3) / cell).floor());
  final i1 = math.min(nx - 1, ((g.center.x + shelfHalfW + 0.3) / cell).ceil());
  final j0 = math.max(1, ((topY - 0.3) / cell).floor());
  final j1 = math.min(ny - 1, ((floorY + _padShelfDepth + 0.3) / cell).ceil());
  for (int j = j0; j <= j1; j++) {
    final y = j * cell;
    for (int i = i0; i <= i1; i++) {
      final x = i * cell;
      final idx = j * (nx + 1) + i;
      final open = _sdBox(x, y, g.center.x, (topY + floorY) / 2, g.halfW, (floorY - topY) / 2);
      final rock = _sdBox(
          x, y, g.center.x, floorY + _padShelfDepth / 2, shelfHalfW, _padShelfDepth / 2);
      field[idx] = math.max(math.min(field[idx], open), -rock);
    }
  }
}

/// Signed distance to an axis-aligned box (negative inside).
double _sdBox(double px, double py, double cx, double cy, double hw, double hh) {
  final dx = (px - cx).abs() - hw;
  final dy = (py - cy).abs() - hh;
  final ox = math.max(dx, 0.0);
  final oy = math.max(dy, 0.0);
  return math.sqrt(ox * ox + oy * oy) + math.min(math.max(dx, dy), 0.0);
}

/// Rock/air boundary loops of a sampled [field] (negative = open): marching
/// squares, then Chaikin smoothing and Douglas-Peucker, dropping specks.
/// Shared by the builder and the runtime [TerrainCarver] re-extract.
/// [extractCaveLoops] on a background isolate. Top-level on purpose: a
/// closure built inside an instance method can capture `this` (the game,
/// with its futures and images), which an isolate message can't carry.
Future<List<List<Pt>>> extractCaveLoopsInBackground(
  Float32List field,
  int nx,
  int ny,
  double cell,
) =>
    Isolate.run(() => extractCaveLoops(field, nx, ny, cell));

List<List<Pt>> extractCaveLoops(Float32List field, int nx, int ny, double cell) {
  final loops = _marchingSquares(field, nx, ny, cell);
  final cleaned = <List<Pt>>[];
  for (var loop in loops) {
    if (loopPerimeter(loop) < 1.2) continue;
    loop = chaikinClosed(loop);
    loop = simplifyClosed(loop, 0.04);
    if (loop.length >= 4) cleaned.add(loop);
  }
  return cleaned;
}

// Edge key: horizontal edge (between (i,j)-(i+1,j)) → id = (j*(nx+1)+i)*2;
// vertical edge (between (i,j)-(i,j+1)) → id = (j*(nx+1)+i)*2+1.
List<List<Pt>> _marchingSquares(Float32List field, int nx, int ny, double cell) {
  int hEdge(int i, int j) => (j * (nx + 1) + i) * 2;
  int vEdge(int i, int j) => (j * (nx + 1) + i) * 2 + 1;

  // Interpolated crossing point on an edge.
  final vertexForEdge = <int, Pt>{};
  Pt crossing(int i0, int j0, int i1, int j1) {
    final f0 = field[j0 * (nx + 1) + i0];
    final f1 = field[j1 * (nx + 1) + i1];
    final t = (f0 / (f0 - f1)).clamp(0.0, 1.0);
    return Pt((i0 + (i1 - i0) * t) * cell, (j0 + (j1 - j0) * t) * cell);
  }

  // links[edgeKey] = up to 2 partner edge keys (each crossing edge belongs
  // to exactly 2 cell-local segments in a watertight field).
  final links = <int, List<int>>{};

  void addSegment(int keyA, Pt posA, int keyB, Pt posB) {
    vertexForEdge[keyA] = posA;
    vertexForEdge[keyB] = posB;
    (links[keyA] ??= <int>[]).add(keyB);
    (links[keyB] ??= <int>[]).add(keyA);
  }

  for (int j = 0; j < ny; j++) {
    for (int i = 0; i < nx; i++) {
      final f00 = field[j * (nx + 1) + i];
      final f10 = field[j * (nx + 1) + i + 1];
      final f01 = field[(j + 1) * (nx + 1) + i];
      final f11 = field[(j + 1) * (nx + 1) + i + 1];

      int caseId = 0;
      if (f00 < 0) caseId |= 1;
      if (f10 < 0) caseId |= 2;
      if (f11 < 0) caseId |= 4;
      if (f01 < 0) caseId |= 8;
      if (caseId == 0 || caseId == 15) continue;

      final top = hEdge(i, j);
      final bottom = hEdge(i, j + 1);
      final left = vEdge(i, j);
      final right = vEdge(i + 1, j);

      Pt topP() => crossing(i, j, i + 1, j);
      Pt bottomP() => crossing(i, j + 1, i + 1, j + 1);
      Pt leftP() => crossing(i, j, i, j + 1);
      Pt rightP() => crossing(i + 1, j, i + 1, j + 1);

      switch (caseId) {
        case 1:
        case 14:
          addSegment(top, topP(), left, leftP());
        case 2:
        case 13:
          addSegment(top, topP(), right, rightP());
        case 3:
        case 12:
          addSegment(left, leftP(), right, rightP());
        case 4:
        case 11:
          addSegment(right, rightP(), bottom, bottomP());
        case 6:
        case 9:
          addSegment(top, topP(), bottom, bottomP());
        case 7:
        case 8:
          addSegment(left, leftP(), bottom, bottomP());
        case 5: // saddle: corners 00 & 11 open — disambiguate by center
        case 10: // saddle: corners 10 & 01 open
          final center = (f00 + f10 + f01 + f11) / 4;
          final openDiagonal = center < 0;
          if (openDiagonal) {
            // open channel along the diagonal
            addSegment(top, topP(), caseId == 5 ? right : left,
                caseId == 5 ? rightP() : leftP());
            addSegment(bottom, bottomP(), caseId == 5 ? left : right,
                caseId == 5 ? leftP() : rightP());
          } else {
            addSegment(top, topP(), caseId == 5 ? left : right,
                caseId == 5 ? leftP() : rightP());
            addSegment(bottom, bottomP(), caseId == 5 ? right : left,
                caseId == 5 ? rightP() : leftP());
          }
      }
    }
  }

  // Walk links into closed loops.
  final loops = <List<Pt>>[];
  final visited = <int>{};
  for (final start in links.keys) {
    if (visited.contains(start)) continue;
    final loop = <Pt>[];
    int? prev;
    int current = start;
    while (true) {
      visited.add(current);
      loop.add(vertexForEdge[current]!);
      final partners = links[current]!;
      int? next;
      for (final p in partners) {
        if (p != prev) {
          next = p;
          break;
        }
      }
      if (next == null) break; // open chain — shouldn't happen (solid border)
      prev = current;
      current = next;
      if (current == start) break;
    }
    if (loop.length >= 3) loops.add(loop);
  }
  return loops;
}
