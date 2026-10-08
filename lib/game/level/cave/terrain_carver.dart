import 'dart:math' as math;
import 'dart:typed_data';

import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';

/// Area that blasts never open (pad floors), in meters.
typedef CarveGuard = ({double x0, double y0, double x1, double y1});

/// Runtime rock removal for a cave level. Works on its own *copy* of the
/// built field (the memoized [BuiltCave] stays pristine, so a restart gets
/// the untouched cave back): each [carve] unions a disc of open space into
/// the field, and [extract] re-runs the builder's contour pass. The world
/// border and [guards] (pad floors) stay solid. Pure Dart, headless-tested.
class TerrainCarver {
  TerrainCarver(BuiltCave cave, {this.guards = const []})
      : field = Float32List.fromList(cave.field),
        nx = cave.nx,
        ny = cave.ny,
        cell = cave.cell;

  final Float32List field;
  final int nx;
  final int ny;
  final double cell;
  final List<CarveGuard> guards;

  /// Rock this close to the world edge is never opened (the cave stays
  /// closed, the camera never shows past it).
  static const double borderMargin = 1.0;

  /// Blend width where a hole meets the cave (soft, rounded edges).
  static const double _blend = 0.3;

  /// Holes opened since the last [extract].
  bool get dirty => _dirty;
  bool _dirty = false;

  /// Opens a disc of radius [r] at ([cx], [cy]). False when nothing changed
  /// (all open already, or guarded).
  bool carve(double cx, double cy, double r) {
    final reach = r + _blend + cell;
    final margin = (borderMargin / cell).ceil();
    final i0 = math.max(margin, ((cx - reach) / cell).floor());
    final i1 = math.min(nx - margin, ((cx + reach) / cell).ceil());
    final j0 = math.max(margin, ((cy - reach) / cell).floor());
    final j1 = math.min(ny - margin, ((cy + reach) / cell).ceil());
    var changed = false;
    for (int j = j0; j <= j1; j++) {
      final y = j * cell;
      for (int i = i0; i <= i1; i++) {
        final x = i * cell;
        if (_guarded(x, y)) continue;
        final dx = x - cx;
        final dy = y - cy;
        final d = math.sqrt(dx * dx + dy * dy) - r;
        final k = j * (nx + 1) + i;
        final f = field[k];
        if (d - f >= _blend) continue;
        final nf = smin(f, d, _blend);
        if (nf < f - 1e-4) {
          field[k] = nf;
          changed = true;
        }
      }
    }
    if (changed) _dirty = true;
    return changed;
  }

  bool _guarded(double x, double y) {
    for (final g in guards) {
      if (x >= g.x0 && x <= g.x1 && y >= g.y0 && y <= g.y1) return true;
    }
    return false;
  }

  /// Current rock/air loops (same pipeline as the level build).
  List<List<Pt>> extract() {
    _dirty = false;
    return extractCaveLoops(field, nx, ny, cell);
  }

  /// A copy of the field for an off-thread [extractCaveLoops]; marks the
  /// carver clean (holes carved after this make it dirty again).
  Float32List snapshot() {
    _dirty = false;
    return Float32List.fromList(field);
  }

  /// Bilinear field lookup (negative = open), like [BuiltCave.fieldAt].
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

/// The floors under the start pad and the delivery pad: blasts leave them.
List<CarveGuard> padGuards({
  required Pt shipSpawn,
  required Pt goalCenter,
  required double goalHalfW,
  required double goalHalfH,
}) =>
    [
      (
        x0: shipSpawn.x - 1.9,
        y0: shipSpawn.y - 0.6,
        x1: shipSpawn.x + 1.9,
        y1: shipSpawn.y + 2.2,
      ),
      (
        x0: goalCenter.x - goalHalfW - 0.5,
        y0: goalCenter.y - goalHalfH - 0.3,
        x1: goalCenter.x + goalHalfW + 0.5,
        y1: goalCenter.y + goalHalfH + 1.8,
      ),
    ];
