import 'dart:math' as math;
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// Pure-Dart route planning over a level's open space: a clearance map
/// (meters to the nearest rock) and a clearance-weighted A* that prefers
/// tunnel centres over hugging walls. Shared by the validator, the preview
/// tool and the autopilot flight test.

/// Signed distance into the nearest well core (positive inside = solid).
double wellCoreField(LevelSpec spec, double x, double y) {
  var best = double.negativeInfinity;
  for (final f in spec.fields) {
    if (f is! GravityWellSpec) continue;
    final d = math.sqrt((x - f.center.x) * (x - f.center.x) + (y - f.center.y) * (y - f.center.y));
    best = math.max(best, f.coreRadius - d);
  }
  return best;
}

/// The cave's sampled field with well cores unioned in as solid rock.
Float32List caveFieldWithCores(BuiltCave cave, LevelSpec spec) {
  if (!spec.fields.any((f) => f is GravityWellSpec)) return cave.field;
  final out = Float32List.fromList(cave.field);
  final stride = cave.nx + 1;
  for (int j = 0; j <= cave.ny; j++) {
    for (int i = 0; i <= cave.nx; i++) {
      final c = wellCoreField(spec, i * cave.cell, j * cave.cell);
      if (c > out[j * stride + i]) out[j * stride + i] = c;
    }
  }
  return out;
}

/// Axis-aligned solid box (TMX wall rectangles), meters.
typedef SolidRect = ({double cx, double cy, double hw, double hh});

/// Turret dome radius (m) — matches `Turret.domeRadius`.
const double kTurretDomeRadius = 0.5;

/// [NavGrid.findPath] `extraCost` at or above this blocks a node.
const double kBlockedCost = 1e6;

class NavGrid {
  NavGrid._(this.nx, this.ny, this.cell, this.clearance);

  /// Grid from a solid mask; clearance is a two-pass chamfer distance
  /// transform (≈1% error), with the world border treated as rock.
  factory NavGrid.fromSolid(int nx, int ny, double cell, bool Function(int i, int j) solid) {
    final stride = nx + 1;
    final d = Float32List(stride * (ny + 1));
    const big = 1e9;
    for (int j = 0; j <= ny; j++) {
      for (int i = 0; i <= nx; i++) {
        final border = i == 0 || j == 0 || i == nx || j == ny;
        d[j * stride + i] = border || solid(i, j) ? 0 : big;
      }
    }
    const a = 1.0;
    const b = math.sqrt2;
    void relax(int k, int i2, int j2, double w) {
      if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) return;
      final v = d[j2 * stride + i2] + w;
      if (v < d[k]) d[k] = v;
    }

    for (int j = 0; j <= ny; j++) {
      for (int i = 0; i <= nx; i++) {
        final k = j * stride + i;
        if (d[k] == 0) continue;
        relax(k, i - 1, j, a);
        relax(k, i, j - 1, a);
        relax(k, i - 1, j - 1, b);
        relax(k, i + 1, j - 1, b);
      }
    }
    for (int j = ny; j >= 0; j--) {
      for (int i = nx; i >= 0; i--) {
        final k = j * stride + i;
        if (d[k] == 0) continue;
        relax(k, i + 1, j, a);
        relax(k, i, j + 1, a);
        relax(k, i + 1, j + 1, b);
        relax(k, i - 1, j + 1, b);
      }
    }
    for (int k = 0; k < d.length; k++) {
      d[k] *= cell;
    }
    return NavGrid._(nx, ny, cell, d);
  }

  /// Cave level: rock where the carved field is ≥ 0 (well cores included),
  /// plus the static defences (turret domes, reactor cores), which are solid
  /// bodies the carved field doesn't know about.
  factory NavGrid.forCave(LevelSpec spec) {
    final cave = buildCave(spec);
    final field = caveFieldWithCores(cave, spec);
    final stride = cave.nx + 1;
    final discs = <(double, double, double)>[
      for (final o in spec.obstacles)
        if (o is TurretSpec)
          (o.base.x, o.base.y, kTurretDomeRadius)
        else if (o is ReactorSpec)
          (o.center.x, o.center.y, o.radius),
    ];
    bool inDisc(double x, double y) {
      for (final (cx, cy, r) in discs) {
        if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) return true;
      }
      return false;
    }

    return NavGrid.fromSolid(
      cave.nx,
      cave.ny,
      cave.cell,
      (i, j) => field[j * stride + i] >= 0 || (discs.isNotEmpty && inDisc(i * cave.cell, j * cave.cell)),
    );
  }

  /// TMX level: wall rectangles on a 0.1 m grid.
  factory NavGrid.forRects(List<SolidRect> rects, double worldW, double worldH,
      {double cell = 0.1}) {
    final nx = (worldW / cell).ceil();
    final ny = (worldH / cell).ceil();
    final mask = Uint8List((nx + 1) * (ny + 1));
    for (final r in rects) {
      final i0 = ((r.cx - r.hw) / cell).floor().clamp(0, nx);
      final i1 = ((r.cx + r.hw) / cell).ceil().clamp(0, nx);
      final j0 = ((r.cy - r.hh) / cell).floor().clamp(0, ny);
      final j1 = ((r.cy + r.hh) / cell).ceil().clamp(0, ny);
      for (int j = j0; j <= j1; j++) {
        for (int i = i0; i <= i1; i++) {
          mask[j * (nx + 1) + i] = 1;
        }
      }
    }
    return NavGrid.fromSolid(nx, ny, cell, (i, j) => mask[j * (nx + 1) + i] == 1);
  }

  final int nx;
  final int ny;
  final double cell;

  /// Meters from each grid node to the nearest rock (0 = rock).
  final Float32List clearance;

  int get _stride => nx + 1;

  /// Bilinear clearance at a world point; 0 outside the grid.
  double clearanceAt(double x, double y) {
    final fx = x / cell;
    final fy = y / cell;
    final ix = fx.floor();
    final iy = fy.floor();
    if (ix < 0 || iy < 0 || ix >= nx || iy >= ny) return 0;
    final u = fx - ix;
    final v = fy - iy;
    final s = _stride;
    final a = clearance[iy * s + ix];
    final b = clearance[iy * s + ix + 1];
    final c = clearance[(iy + 1) * s + ix];
    final d = clearance[(iy + 1) * s + ix + 1];
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  /// Least clearance sampled along the segment a→b.
  double minClearanceAlong(Pt a, Pt b, {double step = 0.05}) {
    final len = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    final n = math.max(1, (len / step).ceil());
    var m = double.infinity;
    for (int k = 0; k <= n; k++) {
      final t = k / n;
      m = math.min(m, clearanceAt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
    }
    return m;
  }

  /// Clearance-weighted A* from [from] to within [tolerance] of [to], over
  /// nodes with at least [minClear] m clearance. Each step costs its length
  /// × (1 + [squeeze]·(shortfall below [comfort])²), so routes ride tunnel
  /// centres and only squeeze where the cave forces it. [extraCost] (per
  /// node, optional) adds to that factor — e.g. how often a moving obstacle
  /// sweeps the node; nodes at ≥ [kBlockedCost] are impassable. Null if
  /// unreachable.
  List<Pt>? findPath(
    Pt from,
    Pt to, {
    required double minClear,
    double comfort = 1.6,
    double squeeze = 8,
    double tolerance = 0.3,
    Float32List? extraCost,
  }) {
    final s = _stride;
    int clampI(double x) => (x / cell).round().clamp(0, nx);
    int clampJ(double y) => (y / cell).round().clamp(0, ny);
    var start = clampJ(from.y) * s + clampI(from.x);
    if (clearance[start] < minClear) {
      // Snap a start that sits just inside the margin to the best nearby node.
      start = _bestNear(from, 0.6, minClear) ?? -1;
      if (start < 0) return null;
    }
    final ti = to.x / cell;
    final tj = to.y / cell;
    final tol = tolerance / cell;

    final n = clearance.length;
    final g = Float64List(n)..fillRange(0, n, double.infinity);
    final parent = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final heap = _Heap();

    double h(int k) {
      final dx = (k % s) - ti;
      final dy = (k ~/ s) - tj;
      return math.sqrt(dx * dx + dy * dy) * cell;
    }

    double weight(int k) {
      final short = math.max(0.0, comfort - clearance[k]) / comfort;
      return 1 + squeeze * short * short + (extraCost?[k] ?? 0);
    }

    g[start] = 0;
    heap.push(start, h(start));
    while (heap.isNotEmpty) {
      final k = heap.pop();
      if (closed[k] == 1) continue;
      closed[k] = 1;
      final i = k % s;
      final j = k ~/ s;
      final dx = i - ti;
      final dy = j - tj;
      if (dx * dx + dy * dy <= tol * tol) {
        final out = <Pt>[];
        for (var c = k; c != -1; c = parent[c]) {
          out.add(Pt((c % s) * cell, (c ~/ s) * cell));
        }
        return out.reversed.toList();
      }
      for (final (di, dj) in _dirs8) {
        final i2 = i + di;
        final j2 = j + dj;
        if (i2 < 0 || j2 < 0 || i2 > nx || j2 > ny) continue;
        final k2 = j2 * s + i2;
        if (closed[k2] == 1 || clearance[k2] < minClear) continue;
        if (extraCost != null && extraCost[k2] >= kBlockedCost) continue;
        if (di != 0 && dj != 0 &&
            (clearance[j * s + i2] < minClear || clearance[j2 * s + i] < minClear)) {
          continue;
        }
        final step = (di != 0 && dj != 0 ? math.sqrt2 : 1.0) * cell;
        final cost = g[k] + step * 0.5 * (weight(k) + weight(k2));
        if (cost < g[k2]) {
          g[k2] = cost;
          parent[k2] = k;
          heap.push(k2, cost + h(k2));
        }
      }
    }
    return null;
  }

  int? _bestNear(Pt p, double radius, double minClear) {
    final s = _stride;
    final r = (radius / cell).ceil();
    final pi = (p.x / cell).round();
    final pj = (p.y / cell).round();
    int? best;
    var bestD = double.infinity;
    for (int dj = -r; dj <= r; dj++) {
      for (int di = -r; di <= r; di++) {
        final i = pi + di;
        final j = pj + dj;
        if (i < 0 || j < 0 || i > nx || j > ny) continue;
        if (clearance[j * s + i] < minClear) continue;
        final d = (di * di + dj * dj).toDouble();
        if (d < bestD) {
          bestD = d;
          best = j * s + i;
        }
      }
    }
    return best;
  }
}

/// Resamples a grid path every [spacing] m and smooths it with a moving
/// average, keeping each point only where the smoothed point still has
/// [minClear] clearance (endpoints are kept exactly).
List<Pt> smoothPath(NavGrid grid, List<Pt> raw, {double spacing = 0.25, double window = 0.8, required double minClear}) {
  if (raw.length < 3) return raw;
  final pts = <Pt>[raw.first];
  var carry = 0.0;
  for (int k = 1; k < raw.length; k++) {
    final a = raw[k - 1];
    final b = raw[k];
    final len = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    var t = spacing - carry;
    while (t <= len) {
      pts.add(Pt(a.x + (b.x - a.x) * t / len, a.y + (b.y - a.y) * t / len));
      t += spacing;
    }
    carry = len - (t - spacing);
  }
  if (pts.last.x != raw.last.x || pts.last.y != raw.last.y) pts.add(raw.last);
  final half = math.max(1, (window / spacing / 2).round());
  final out = <Pt>[pts.first];
  for (int k = 1; k < pts.length - 1; k++) {
    var sx = 0.0;
    var sy = 0.0;
    var n = 0;
    for (int m = math.max(0, k - half); m <= math.min(pts.length - 1, k + half); m++) {
      sx += pts[m].x;
      sy += pts[m].y;
      n++;
    }
    final sm = Pt(sx / n, sy / n);
    out.add(grid.clearanceAt(sm.x, sm.y) >= minClear ? sm : pts[k]);
  }
  out.add(pts.last);
  return out;
}

/// Total length of a polyline (m).
double pathLength(List<Pt> path) {
  var len = 0.0;
  for (int k = 1; k < path.length; k++) {
    final dx = path[k].x - path[k - 1].x;
    final dy = path[k].y - path[k - 1].y;
    len += math.sqrt(dx * dx + dy * dy);
  }
  return len;
}

const _dirs8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

/// Binary min-heap of (node, priority) for A*.
class _Heap {
  final _keys = <int>[];
  final _pri = <double>[];
  bool get isNotEmpty => _keys.isNotEmpty;

  void push(int k, double p) {
    _keys.add(k);
    _pri.add(p);
    var i = _keys.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_pri[parent] <= _pri[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _keys.first;
    final lastK = _keys.removeLast();
    final lastP = _pri.removeLast();
    if (_keys.isNotEmpty) {
      _keys[0] = lastK;
      _pri[0] = lastP;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _keys.length && _pri[l] < _pri[m]) m = l;
        if (r < _keys.length && _pri[r] < _pri[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = k;
    final p = _pri[a];
    _pri[a] = _pri[b];
    _pri[b] = p;
  }
}
