import 'package:narrow_haul/game/level/cave/geom.dart';

/// Hand-authored organic cave level. Everything is const data; the terrain
/// shape is a pure function of this spec (noise seeded by [seed]), so a level
/// is always identical on every run and device.
class LevelSpec {
  const LevelSpec({
    required this.id,
    required this.seed,
    required this.name,
    required this.themeId,
    required this.worldW,
    required this.worldH,
    required this.tunnels,
    this.chambers = const <ChamberSpec>[],
    required this.shipSpawn,
    required this.cargoSpawn,
    required this.goal,
    this.obstacles = const <ObstacleSpec>[],
    this.fields = const <FieldSpec>[],
    this.modifiers = const LevelModifiers(),
    this.noise = const NoiseSpec(),
    this.shipId,
  });

  final String id;
  final int seed;
  final String name;
  final String themeId;
  final double worldW;
  final double worldH;
  final List<TunnelSpec> tunnels;
  final List<ChamberSpec> chambers;
  final Pt shipSpawn;
  final Pt cargoSpawn;
  final GoalSpec goal;
  final List<ObstacleSpec> obstacles;

  /// Gravity zones, wind and gravity wells (see [FieldSpec]).
  final List<FieldSpec> fields;
  final LevelModifiers modifiers;
  final NoiseSpec noise;

  /// Ship override (see `kShips`); null → the world's default ship.
  final String? shipId;
}

/// Winding corridor: a Catmull-Rom spline through [points] carved as capsules.
/// [widths] are per-point half-widths (meters) — vary them for wide chambers
/// narrowing into squeezes. Falls back to uniform [width].
class TunnelSpec {
  const TunnelSpec(this.points, {this.width = 1.2, this.widths});

  final List<Pt> points;
  final double width;
  final List<double>? widths;

  List<double> get radii =>
      widths ?? List<double>.filled(points.length, width, growable: false);
}

/// Bulbous open pocket (ellipse), the "rooms" of the ant nest.
class ChamberSpec {
  const ChamberSpec(this.center, this.rx, [double? ry]) : ry = ry ?? rx;
  final Pt center;
  final double rx;
  final double ry;
}

class GoalSpec {
  const GoalSpec(this.center, {this.halfW = 1.6, this.halfH = 1.1});
  final Pt center;
  final double halfW;
  final double halfH;
}

/// Per-level physics tweaks. Multipliers compose with daily-challenge ones.
class LevelModifiers {
  const LevelModifiers({
    this.gravityMul = 1.0,
    this.fuelDrainMul = 1.0,
    this.cargoDensityMul = 1.0,
    this.wallFriction,
  });

  final double gravityMul;
  final double fuelDrainMul;
  final double cargoDensityMul;

  /// Terrain friction override — ice caverns use ~0.03. Null → default 0.35.
  final double? wallFriction;

  bool get isDefault =>
      gravityMul == 1.0 &&
      fuelDrainMul == 1.0 &&
      cargoDensityMul == 1.0 &&
      wallFriction == null;
}

/// Organic boundary roughness. Amplitude is capped by the validation test,
/// not just by convention — corridors must keep ship clearance.
class NoiseSpec {
  const NoiseSpec({this.amplitude = 0.3, this.frequency = 0.42, this.octaves = 3});
  final double amplitude;
  final double frequency;
  final int octaves;
}

/// Fuel/time thresholds for the 3-star rating of one level.
class StarSpec {
  const StarSpec({this.star3Fuel = 0.7, this.star2Fuel = 0.4, this.star3Time = 60});
  final double star3Fuel;
  final double star2Fuel;
  final double star3Time;
}

// ── Obstacles (all kill the ship on contact, like terrain) ────────────────

sealed class ObstacleSpec {
  const ObstacleSpec();
}

/// Kinematic bar spinning at constant [radPerSec] around [center].
class RotatingBarSpec extends ObstacleSpec {
  const RotatingBarSpec(
    this.center, {
    required this.halfLength,
    this.thickness = 0.15,
    required this.radPerSec,
    this.initialAngle = 0,
  });
  final Pt center;
  final double halfLength;
  final double thickness;
  final double radPerSec;
  final double initialAngle;
}

/// Bob swinging below [pivot] on an analytic (kinematic) arc — deterministic
/// and unaffected by gravity modifiers, unlike a free joint.
class PendulumSpec extends ObstacleSpec {
  const PendulumSpec(
    this.pivot, {
    required this.length,
    this.bobRadius = 0.35,
    required this.amplitudeRad,
    required this.periodSec,
    this.phase = 0,
  });
  final Pt pivot;
  final double length;
  final double bobRadius;
  final double amplitudeRad;
  final double periodSec;
  final double phase;
}

/// Block oscillating between [from] and [to] on a cosine ease.
class SlidingBlockSpec extends ObstacleSpec {
  const SlidingBlockSpec(
    this.from,
    this.to, {
    required this.halfW,
    required this.halfH,
    required this.periodSec,
    this.phase = 0,
  });
  final Pt from;
  final Pt to;
  final double halfW;
  final double halfH;
  final double periodSec;
  final double phase;
}

// ── Force fields (extra acceleration on ship + cargo) ─────────────────────
//
// All strengths are in "g units": multiples of the base gravity constant
// (kGravityY, already debug/daily-challenge scaled at runtime), so a field
// keeps its feel relative to normal gravity. +Y points down.

enum FieldShape { rect, ellipse }

sealed class FieldSpec {
  const FieldSpec();
}

/// Region whose gravity is *replaced* by ([gx], [gy]) g. (0, 0) = zero-g
/// pocket; (1, 0) = pull to the right. Inside the shape the zone ramps in
/// over [feather] meters from its edge, so crossing it never jolts.
/// Overlapping zones apply in list order (later wins).
class GravityZoneSpec extends FieldSpec {
  const GravityZoneSpec(
    this.center, {
    this.shape = FieldShape.rect,
    required this.halfW,
    required this.halfH,
    required this.gx,
    required this.gy,
    this.feather = 1.0,
  });
  final Pt center;
  final FieldShape shape;
  final double halfW;
  final double halfH;
  final double gx;
  final double gy;
  final double feather;
}

/// Wind / current *added* on top of gravity: ([ax], [ay]) g, optionally
/// gusting by ±[gustAmp] (fraction) over [gustPeriod] seconds. Cargo feels
/// [cargoFactor] of it (tiny cargo vs. big hull).
class WindZoneSpec extends FieldSpec {
  const WindZoneSpec(
    this.center, {
    this.shape = FieldShape.rect,
    required this.halfW,
    required this.halfH,
    required this.ax,
    required this.ay,
    this.feather = 1.0,
    this.gustAmp = 0,
    this.gustPeriod = 4,
    this.cargoFactor = 1.0,
  });
  final Pt center;
  final FieldShape shape;
  final double halfW;
  final double halfH;
  final double ax;
  final double ay;
  final double feather;
  final double gustAmp;
  final double gustPeriod;
  final double cargoFactor;
}

/// Point attractor: pull = [strength] / (r² + [softening]²) g toward
/// [center], capped at [maxG]. The solid core ([coreRadius]) is terrain.
class GravityWellSpec extends FieldSpec {
  const GravityWellSpec(
    this.center, {
    required this.strength,
    this.softening = 1.5,
    this.coreRadius = 0.8,
    this.maxG = 3.0,
  });
  final Pt center;
  final double strength;
  final double softening;
  final double coreRadius;
  final double maxG;
}
