import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/cave/obstacle_paths.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// How hard a cave level is to *finish* (not to 3★): what a pilot meets along
/// the route a careful pilot would fly (clearance-weighted A*, tunnel
/// centres). Pure Dart, for `tool/difficulty_curve.dart` and its test.

/// Route clearance (beyond the ship's circumradius) under which a stretch
/// counts as a squeeze.
const double kSqueezeMargin = 0.8;

/// A route point this close (beyond the circumradius) to a moving obstacle's
/// sweep has to be timed.
const double kSweepMargin = 0.3;

/// A field stretch: local pull differs from the level's base gravity by more
/// than this many g.
const double kFieldDeltaG = 0.15;

class CourseMetrics {
  const CourseMetrics({
    required this.length,
    required this.minMargin,
    required this.squeezeMeters,
    required this.towSqueezeMeters,
    required this.turnQuarters,
    required this.sweepMeters,
    required this.timingGates,
    required this.turretsOnRoute,
    required this.fieldMeters,
    required this.gravityMul,
    required this.cargoMul,
    required this.slippery,
    required this.liftRatio,
    required this.fuelFraction,
  });

  /// Metres flown spawn → pod → pad (every leg of an Expedition).
  final double length;

  /// Tightest clearance on the route beyond the ship's circumradius (m).
  final double minMargin;

  /// Route metres with less than [kSqueezeMargin] to spare, empty / towing.
  final double squeezeMeters;
  final double towSqueezeMeters;

  /// Total heading change along the route, in quarter turns (90°).
  final double turnQuarters;

  /// Route metres inside a moving obstacle's sweep, and how many separate
  /// obstacles the route has to time.
  final double sweepMeters;
  final int timingGates;

  /// Turrets whose range reaches the route.
  final int turretsOnRoute;

  /// Route metres where a field changes the pull.
  final double fieldMeters;

  final double gravityMul;
  final double cargoMul;

  /// Low-friction rock (ice): landings slide.
  final bool slippery;

  /// Loaded thrust ÷ strongest pull (validator, heaviest daily gravity).
  final double liftRatio;

  /// Validator's fuel floor estimate (share of the tank).
  final double fuelFraction;
}

/// Null if the level has no route for [ship].
CourseMetrics? measureCourse(LevelSpec spec, {required ShipSpec ship}) {
  final grid = NavGrid.forCave(spec);
  final minClear = ship.circumradius + 0.04;
  final sampler = FieldSampler(
    fields: spec.fields,
    g0: kGravityY,
    gravityMul: spec.modifiers.gravityMul,
  );
  final base = sampler.baseAccel;

  var length = 0.0;
  var minMargin = double.infinity;
  var squeeze = 0.0;
  var towSqueeze = 0.0;
  var turn = 0.0;
  var sweep = 0.0;
  var field = 0.0;
  final gates = <int>{};
  final turrets = <int>{};

  final movers = [
    for (final (k, o) in spec.obstacles.indexed)
      if (o is RotatingBarSpec || o is PendulumSpec || o is SlidingBlockSpec) (k, o),
  ];

  var from = spec.shipSpawn;
  for (var leg = 0; leg < spec.allLegs.length; leg++) {
    final l = spec.allLegs[leg];
    if (leg > 0) from = legShipSpawn(spec.allLegs[leg - 1].goal);
    final toPod = grid.findPath(from, l.cargoSpawn, minClear: minClear, tolerance: 1.15);
    if (toPod == null) return null;
    final toPad = grid.findPath(toPod.last, l.goal.center, minClear: minClear, tolerance: 0.8);
    if (toPad == null) return null;

    for (final (path, towing) in [(toPod, false), (toPad, true)]) {
      final pts = _resample(path, 0.25);
      for (var n = 1; n < pts.length; n++) {
        final p = pts[n];
        final ds = _dist(pts[n - 1], p);
        length += ds;
        final margin = grid.clearanceAt(p.x, p.y) - ship.circumradius;
        minMargin = math.min(minMargin, margin);
        if (margin < kSqueezeMargin) {
          if (towing) {
            towSqueeze += ds;
          } else {
            squeeze += ds;
          }
        }
        var inSweep = false;
        for (final (k, o) in movers) {
          if (_sweepDistance(o, p) < ship.circumradius + kSweepMargin) {
            inSweep = true;
            gates.add(k);
          }
        }
        if (inSweep) sweep += ds;
        for (final (k, o) in spec.obstacles.indexed) {
          if (o is TurretSpec && _dist(o.base, p) <= o.range) turrets.add(k);
        }
        if (sampler.fields.isNotEmpty) {
          final a = sampler.accelAt(p.x, p.y);
          final d = math.sqrt((a.x - base.x) * (a.x - base.x) + (a.y - base.y) * (a.y - base.y));
          if (d > kFieldDeltaG * kGravityY) field += ds;
        }
      }
      turn += _headingChange(_resample(path, 1.0));
    }
  }

  final flight = analyzeFlight(spec, ship: ship);
  return CourseMetrics(
    length: length,
    minMargin: minMargin,
    squeezeMeters: squeeze,
    towSqueezeMeters: towSqueeze,
    turnQuarters: turn / (math.pi / 2),
    sweepMeters: sweep,
    timingGates: gates.length,
    turretsOnRoute: turrets.length,
    fieldMeters: field,
    gravityMul: spec.modifiers.gravityMul,
    cargoMul: spec.modifiers.cargoDensityMul,
    slippery: (spec.modifiers.wallFriction ?? 1) < 0.1,
    liftRatio: flight?.liftRatio ?? 1,
    fuelFraction: flight?.fuelFraction ?? 1,
  );
}

/// What the autopilot saw flying it (build/autopilot_report.json): pilot
/// profiles that delivered with hazards on, and the best flight's time spent
/// holding short of obstacles / under a turret's eye.
typedef BotStats = ({int profilesOk, int profiles, double heldSeconds, double exposedSeconds});

/// 0–100 completion difficulty. Weights: squeeze 25, timing & turrets 25,
/// length & turns 20, physics 20, bot 10 (without bot stats its 10 points
/// and the bot's waiting/exposure share of timing are left out and the rest
/// rescaled).
double completionScore(CourseMetrics m, {BotStats? bot}) {
  double c(double v) => v.clamp(0.0, 1.0).toDouble();
  // A towed squeeze is harder: the pod swings into the rock.
  final squeeze = c((m.squeezeMeters + 1.6 * m.towSqueezeMeters) / 20) * 12 +
      c((0.75 - m.minMargin) / 0.45) * 13;
  final timing = c(m.sweepMeters / 10) * 6 +
      c(m.timingGates / 3) * 7 +
      c(m.turretsOnRoute / 3) * 8 +
      (bot == null ? 0 : c(bot.heldSeconds / 10) * 2 + c(bot.exposedSeconds / 15) * 2);
  final route = c((m.length - 20) / 50) * 10 + c((m.turnQuarters - 2) / 7) * 10;
  // Zero-g drifts: as hard to hold as a heavy level.
  final g = m.gravityMul == 0 ? 1.3 : m.gravityMul;
  final physics = c((g - 0.6) / 1.1) * 7 +
      c((m.cargoMul - 1) / 1.2) * 4 +
      c(m.fieldMeters / 25) * 5 +
      (m.slippery ? 2 : 0) +
      c((3.5 - m.liftRatio) / 2) * 2;
  final botPart = bot == null
      ? 0.0
      : 10 * math.max(0, bot.profiles - bot.profilesOk) / bot.profiles;
  final raw = squeeze + timing + route + physics + botPart;
  final max = bot == null ? 86.0 : 100.0;
  return (raw / max * 1000).round() / 10;
}

// ── Curve ──────────────────────────────────────────────────────────────────

/// A world's missions in play order with their completion scores. The type
/// rating, if any, is left out (it's a short check ride, not a mission).
typedef WorldCurve = ({String world, List<(String id, double score)> levels});

/// How far a level may drop below the one before it (one breather after a
/// spike), and how far the finale may sit under the world's peak.
const double kCurveDipTolerance = 12;
const double kFinaleTolerance = 8;

/// Score differences under this are noise, not a dip.
const double kCurveNoise = 3;

/// An opener may sit this far over its world's median, or this far under
/// the previous world's median (a new ship and mechanic count for the rest).
const double kOpenerOverMedian = 5;
const double kOpenerUnderPrevMedian = 15;

double curveMedian(List<double> xs) {
  final s = [...xs]..sort();
  if (s.isEmpty) return 0;
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Everything that breaks the sawtooth: inside a world the difficulty rises
/// (one dip up to [kCurveDipTolerance] allowed) to a finale near the peak; a
/// world opens near the previous world's median; medians and peaks rise
/// world to world.
List<String> curveFlags(List<WorldCurve> worlds) {
  final flags = <String>[];
  double? prevMedian;
  double? prevPeak;
  for (final w in worlds) {
    final scores = [for (final (_, s) in w.levels) s];
    if (scores.isEmpty) continue;
    final median = curveMedian(scores);
    final peak = scores.reduce(math.max);
    final (openId, open) = w.levels.first;
    if (open > median + kOpenerOverMedian) {
      flags.add('${w.world}: opener $openId (${_f(open)}) is above the world median (${_f(median)})');
    }
    if (prevMedian != null && open < prevMedian - kOpenerUnderPrevMedian) {
      flags.add('${w.world}: opener $openId (${_f(open)}) drops far below the previous world median (${_f(prevMedian)})');
    }
    var dips = 0;
    for (var k = 1; k < w.levels.length; k++) {
      final (id, s) = w.levels[k];
      final (prevId, p) = w.levels[k - 1];
      if (s >= p - kCurveNoise) continue;
      dips++;
      if (p - s > kCurveDipTolerance) {
        flags.add('${w.world}: $prevId (${_f(p)}) → $id (${_f(s)}) drops ${_f(p - s)}');
      } else if (dips > 1) {
        flags.add('${w.world}: $prevId (${_f(p)}) → $id (${_f(s)}) is another dip');
      }
    }
    final (finId, fin) = w.levels.last;
    if (fin < peak - kFinaleTolerance) {
      flags.add('${w.world}: finale $finId (${_f(fin)}) is well under the world peak (${_f(peak)})');
    }
    if (prevMedian != null && median < prevMedian) {
      flags.add('${w.world}: median ${_f(median)} is below the previous world (${_f(prevMedian)})');
    }
    if (prevPeak != null && peak < prevPeak) {
      flags.add('${w.world}: peak ${_f(peak)} is below the previous world (${_f(prevPeak)})');
    }
    prevMedian = median;
    prevPeak = peak;
  }
  return flags;
}

String _f(double v) => v.toStringAsFixed(0);

// ── Geometry ───────────────────────────────────────────────────────────────

double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// Points every [step] metres along a polyline (grid paths zig-zag, so turns
/// are measured on a coarse resample).
List<Pt> _resample(List<Pt> path, double step) {
  if (path.length < 2) return path;
  final out = <Pt>[path.first];
  var carry = 0.0;
  for (var n = 1; n < path.length; n++) {
    final a = path[n - 1];
    final b = path[n];
    final len = _dist(a, b);
    var t = step - carry;
    while (t <= len) {
      out.add(Pt(a.x + (b.x - a.x) * t / len, a.y + (b.y - a.y) * t / len));
      t += step;
    }
    carry = len - (t - step);
  }
  if (_dist(out.last, path.last) > step * 0.25) out.add(path.last);
  return out;
}

double _headingChange(List<Pt> pts) {
  var sum = 0.0;
  for (var n = 2; n < pts.length; n++) {
    final a1 = math.atan2(pts[n - 1].y - pts[n - 2].y, pts[n - 1].x - pts[n - 2].x);
    final a2 = math.atan2(pts[n].y - pts[n - 1].y, pts[n].x - pts[n - 1].x);
    var d = (a2 - a1).abs();
    if (d > math.pi) d = 2 * math.pi - d;
    sum += d;
  }
  return sum;
}

double _box(double lx, double ly, double hw, double hh) {
  final dx = lx.abs() - hw;
  final dy = ly.abs() - hh;
  return math.sqrt(math.pow(math.max(dx, 0.0), 2) + math.pow(math.max(dy, 0.0), 2)) +
      math.min(math.max(dx, dy), 0.0);
}

/// Closest a moving obstacle ever comes to [p] over one cycle.
double _sweepDistance(ObstacleSpec o, Pt p) {
  const samples = 32;
  var best = double.infinity;
  switch (o) {
    case RotatingBarSpec s:
      final dx = p.x - s.center.x;
      final dy = p.y - s.center.y;
      if (math.sqrt(dx * dx + dy * dy) - s.halfLength - s.thickness > 1) return double.infinity;
      for (var k = 0; k < samples; k++) {
        final a = math.pi * k / samples;
        final ca = math.cos(a);
        final sa = math.sin(a);
        best = math.min(best, _box(dx * ca + dy * sa, -dx * sa + dy * ca, s.halfLength, s.thickness));
      }
    case PendulumSpec s:
      for (var k = 0; k < samples; k++) {
        final b = pendulumBobAt(s, s.periodSec * k / samples);
        best = math.min(best, _dist(b, p) - s.bobRadius);
      }
    case SlidingBlockSpec s:
      for (var k = 0; k < samples; k++) {
        final b = slidingBlockAt(s, s.periodSec * k / samples);
        best = math.min(best, _box(p.x - b.x, p.y - b.y, s.halfW, s.halfH));
      }
    default:
  }
  return best;
}
