// What the autopilot knows about moving obstacles: exact future positions
// (from the shared analytic paths) and a per-node occupancy map for routing.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/obstacle_paths.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

/// One moving obstacle: signed distance from a point to its solid shape at
/// [dt] seconds from now, plus its period (for sweep maps).
class _Mover {
  _Mover(this.distance, this.period, this.bounds);
  final double Function(double x, double y, double dt) distance;
  final double period;

  /// Sweep bounding box (minX, minY, maxX, maxY), meters.
  final (double, double, double, double) bounds;
}

double _boxDistance(double lx, double ly, double hw, double hh) {
  final dx = lx.abs() - hw;
  final dy = ly.abs() - hh;
  final ox = math.max(dx, 0.0);
  final oy = math.max(dy, 0.0);
  return math.sqrt(ox * ox + oy * oy) + math.min(math.max(dx, dy), 0.0);
}

class ObstacleHazards {
  ObstacleHazards._(this._movers);

  /// Reads the live obstacle components (their clocks) from [game].
  factory ObstacleHazards.of(NarrowHaulGame game) {
    final movers = <_Mover>[];
    for (final c in game.world.children) {
      switch (c) {
        case RotatingBar bar:
          final s = bar.spec;
          final omega = s.radPerSec;
          final r = s.halfLength + s.thickness;
          movers.add(_Mover(
            (x, y, dt) {
              final a = bar.body.angle + omega * dt;
              final dx = x - s.center.x;
              final dy = y - s.center.y;
              final ca = math.cos(a);
              final sa = math.sin(a);
              return _boxDistance(dx * ca + dy * sa, -dx * sa + dy * ca, s.halfLength, s.thickness);
            },
            omega.abs() < 1e-6 ? 1 : math.pi / omega.abs(),
            (s.center.x - r, s.center.y - r, s.center.x + r, s.center.y + r),
          ));
        case Pendulum p:
          final s = p.spec;
          var minX = double.infinity, minY = double.infinity;
          var maxX = -double.infinity, maxY = -double.infinity;
          for (var k = 0; k < 64; k++) {
            final b = pendulumBobAt(s, s.periodSec * k / 64);
            minX = math.min(minX, b.x);
            minY = math.min(minY, b.y);
            maxX = math.max(maxX, b.x);
            maxY = math.max(maxY, b.y);
          }
          movers.add(_Mover(
            (x, y, dt) {
              final b = pendulumBobAt(s, p.time + dt);
              return math.sqrt((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y)) - s.bobRadius;
            },
            s.periodSec,
            (minX - s.bobRadius, minY - s.bobRadius, maxX + s.bobRadius, maxY + s.bobRadius),
          ));
        case SlidingBlock b:
          final s = b.spec;
          movers.add(_Mover(
            (x, y, dt) {
              final c = slidingBlockAt(s, b.time + dt);
              return _boxDistance(x - c.x, y - c.y, s.halfW, s.halfH);
            },
            s.periodSec,
            (
              math.min(s.from.x, s.to.x) - s.halfW,
              math.min(s.from.y, s.to.y) - s.halfH,
              math.max(s.from.x, s.to.x) + s.halfW,
              math.max(s.from.y, s.to.y) + s.halfH,
            ),
          ));
        default:
          break;
      }
    }
    return ObstacleHazards._(movers);
  }

  final List<_Mover> _movers;

  bool get isEmpty => _movers.isEmpty;

  /// Distance from (x, y) to the nearest obstacle surface [dt] s from now.
  double distanceAt(double x, double y, double dt) {
    var m = double.infinity;
    for (final o in _movers) {
      m = math.min(m, o.distance(x, y, dt));
    }
    return m;
  }

  /// Per-node routing cost on [grid]: [weight] × the fraction of a period the node
  /// is within [margin] of an obstacle; always-occupied nodes are blocked.
  /// With [blockAll], every node an obstacle ever reaches is blocked.
  Float32List occupancyCost(NavGrid grid, double margin, {bool blockAll = false, double weight = 3}) {
    final cost = Float32List(grid.clearance.length);
    final stride = grid.nx + 1;
    const samples = 48;
    for (final o in _movers) {
      final (x0, y0, x1, y1) = o.bounds;
      final i0 = ((x0 - margin) / grid.cell).floor().clamp(0, grid.nx);
      final i1 = ((x1 + margin) / grid.cell).ceil().clamp(0, grid.nx);
      final j0 = ((y0 - margin) / grid.cell).floor().clamp(0, grid.ny);
      final j1 = ((y1 + margin) / grid.cell).ceil().clamp(0, grid.ny);
      for (var j = j0; j <= j1; j++) {
        for (var i = i0; i <= i1; i++) {
          final x = i * grid.cell;
          final y = j * grid.cell;
          var hit = 0;
          for (var k = 0; k < samples; k++) {
            if (o.distance(x, y, o.period * k / samples) < margin) hit++;
          }
          if (hit == 0) continue;
          final f = hit / samples;
          final k = j * stride + i;
          cost[k] = f >= 0.97 || blockAll ? kBlockedCost : math.max(cost[k], weight * f);
        }
      }
    }
    return cost;
  }

  /// True if the node near [p] is ever within [margin] of an obstacle.
  bool sweeps(Pt p, double margin) {
    for (final o in _movers) {
      final (x0, y0, x1, y1) = o.bounds;
      if (p.x < x0 - margin || p.x > x1 + margin || p.y < y0 - margin || p.y > y1 + margin) continue;
      for (var k = 0; k < 48; k++) {
        if (o.distance(p.x, p.y, o.period * k / 48) < margin) return true;
      }
    }
    return false;
  }
}

/// Turrets that can still shoot (none while the reactor has them offline).
List<Turret> liveTurrets(NarrowHaulGame game) => game.turretsDisabled
    ? const []
    : [
        for (final c in game.world.children)
          if (c is Turret && !c.destroyed) c,
      ];

/// The level's reactor, if it's still standing.
Reactor? liveReactor(NarrowHaulGame game) {
  for (final c in game.world.children) {
    if (c is Reactor && !c.destroyed) return c;
  }
  return null;
}

double _angleDelta(double from, double to) {
  var d = (to - from) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  return d;
}

/// Cave-only line of sight between two points (defences and the pod are
/// ignored — conservative for "can it see me").
bool caveSight(NavGrid grid, Pt a, Pt b, {double margin = 0.02}) =>
    grid.minClearanceAlong(a, b, step: 0.1) > margin;

/// Could turret [t] shoot at a ship at [p]? Same test as `Turret.update`
/// (range and arc from the base, sight from the muzzle), padded by [extra].
bool turretSees(NavGrid grid, TurretSpec t, Pt p, {double extra = 0.3, double arcPad = 0.1}) {
  final dx = p.x - t.base.x;
  final dy = p.y - t.base.y;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist > t.range + extra) return false;
  final bearing = math.atan2(dy, dx);
  if (_angleDelta(t.facing, bearing).abs() > t.aimArc + arcPad) return false;
  // Muzzle sits 1.1 m out along the barrel, which points at the target.
  final muzzle = Pt(t.base.x + dx / dist * 1.1, t.base.y + dy / dist * 1.1);
  return dist <= 1.1 || caveSight(grid, muzzle, p);
}

/// Point to shoot at (inside the dome, just off the wall).
Pt domeAim(TurretSpec t) =>
    Pt(t.base.x + math.cos(t.facing) * 0.3, t.base.y + math.sin(t.facing) * 0.3);

/// Just outside the dome along its facing: a clear-sight target point.
Pt domeFront(TurretSpec t) =>
    Pt(t.base.x + math.cos(t.facing) * 0.7, t.base.y + math.sin(t.facing) * 0.7);
