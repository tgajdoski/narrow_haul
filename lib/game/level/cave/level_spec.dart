import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/physics_core.dart';

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
    this.pickups = const <PickupSpec>[],
    this.modifiers = const LevelModifiers(),
    this.noise = const NoiseSpec(),
    this.shipId,
    this.cargoClamped = false,
    this.legs = const <LegSpec>[],
  });

  /// An Expedition: several hauls in one cave (docs/STORY.md §3). Leg 1's
  /// pod and pad are also [cargoSpawn] / [goal], so every single-leg check
  /// and tool sees the first haul; [allLegs] has them all.
  LevelSpec.expedition({
    required this.id,
    required this.seed,
    required this.name,
    required this.themeId,
    required this.worldW,
    required this.worldH,
    required this.tunnels,
    this.chambers = const <ChamberSpec>[],
    required this.shipSpawn,
    required this.legs,
    this.obstacles = const <ObstacleSpec>[],
    this.fields = const <FieldSpec>[],
    this.pickups = const <PickupSpec>[],
    this.modifiers = const LevelModifiers(),
    this.noise = const NoiseSpec(),
    this.shipId,
  })  : assert(legs.length >= 2, 'an expedition has at least two legs'),
        cargoSpawn = legs.first.cargoSpawn,
        goal = legs.first.goal,
        cargoClamped = legs.first.cargoClamped;

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

  /// Fuel cells and other fly-through collectibles (see [PickupSpec]).
  final List<PickupSpec> pickups;
  final LevelModifiers modifiers;
  final NoiseSpec noise;

  /// Ship override (see `kShips`); null → the world's default ship.
  final String? shipId;

  /// Cargo lock: the pod is held in place until hooked. Required wherever
  /// the pull at the cargo isn't calm and downward (zero-g, near wells).
  final bool cargoClamped;

  /// An Expedition's hauls in order (empty for a one-haul mission).
  final List<LegSpec> legs;

  /// Every haul: [legs], or the one from [cargoSpawn] / [goal].
  List<LegSpec> get allLegs =>
      legs.isNotEmpty ? legs : [LegSpec(cargoSpawn, goal, cargoClamped: cargoClamped)];

  bool get isExpedition => legs.length > 1;

  /// Every pad and pod of every leg, plus the spawn: where the builder calms
  /// the rock, lays pad shelves, and nothing else may be placed.
  List<Pt> get anchorPoints => [
        shipSpawn,
        cargoSpawn,
        goal.center,
        for (final l in legs) ...[l.cargoSpawn, l.goal.center],
      ];

  /// Every pad, in leg order ([goal] is always one of them).
  List<GoalSpec> get allGoals => [for (final l in allLegs) l.goal];

  /// Leg [k] as a one-haul mission in the same cave (validation and flight
  /// estimates): the ship starts on the previous leg's pad, [legs] are kept
  /// so the cave builds the same (and shares the cache entry).
  LevelSpec forLeg(int k) {
    final l = allLegs[k];
    return LevelSpec(
      id: id,
      seed: seed,
      name: name,
      themeId: themeId,
      worldW: worldW,
      worldH: worldH,
      tunnels: tunnels,
      chambers: chambers,
      shipSpawn: k == 0 ? shipSpawn : legShipSpawn(allLegs[k - 1].goal),
      cargoSpawn: l.cargoSpawn,
      goal: l.goal,
      obstacles: obstacles,
      fields: fields,
      pickups: pickups,
      modifiers: modifiers,
      noise: noise,
      shipId: shipId,
      cargoClamped: k > 0 || l.cargoClamped,
      legs: legs,
    );
  }

  /// This level with some parts swapped (authoring tools and tests). Keeps
  /// [id], so it shares the original's cave cache entry unless given a new one.
  LevelSpec copyWith({
    String? id,
    List<ObstacleSpec>? obstacles,
    List<FieldSpec>? fields,
    List<PickupSpec>? pickups,
    LevelModifiers? modifiers,
    String? shipId,
    bool? cargoClamped,
  }) =>
      LevelSpec(
        id: id ?? this.id,
        seed: seed,
        name: name,
        themeId: themeId,
        worldW: worldW,
        worldH: worldH,
        tunnels: tunnels,
        chambers: chambers,
        shipSpawn: shipSpawn,
        cargoSpawn: cargoSpawn,
        goal: goal,
        obstacles: obstacles ?? this.obstacles,
        fields: fields ?? this.fields,
        pickups: pickups ?? this.pickups,
        modifiers: modifiers ?? this.modifiers,
        noise: noise,
        shipId: shipId ?? this.shipId,
        cargoClamped: cargoClamped ?? this.cargoClamped,
        legs: legs,
      );
}

/// One haul of an Expedition: a pod and the pad it goes to. Landing it on
/// the pad refuels the ship and saves a checkpoint; the next leg's pod
/// waits locked ([cargoClamped] is forced on for every leg after the first)
/// until it is hooked.
class LegSpec {
  const LegSpec(this.cargoSpawn, this.goal, {this.cargoClamped = false});
  final Pt cargoSpawn;
  final GoalSpec goal;
  final bool cargoClamped;
}

/// Where the ship starts a leg after landing the previous one on [pad]:
/// right of the pad's centre, clear of the parked pod on its left.
Pt legShipSpawn(GoalSpec pad) => Pt(pad.center.x + 0.4, pad.center.y);

/// Where a delivered pod is parked on [pad] (a checkpoint resume).
Pt legParkedPod(GoalSpec pad) =>
    Pt(pad.center.x - pad.halfW + 0.45, padFloorY(pad) - kCargoRadius);

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

/// World y of the flat rock shelf the builder lays under [g].
double padFloorY(GoalSpec g) => g.center.y + g.halfH + kPadFloorDrop;

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

  /// Fuel left and time good enough for ★★★ (before any cap).
  bool earnsThree(double fuelFraction, double seconds) =>
      fuelFraction >= star3Fuel && seconds <= star3Time;

  bool earnsTwo(double fuelFraction) => fuelFraction >= star2Fuel;

  /// The one star rule. [capped]: a continued, guided or carried-weapon run,
  /// which can never be perfect.
  int rate(double fuelFraction, double seconds, {bool capped = false}) {
    if (!capped && earnsThree(fuelFraction, seconds)) return 3;
    return earnsTwo(fuelFraction) ? 2 : 1;
  }
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

/// Wall-mounted defence turret. [base] sits on the cave wall and [facing]
/// (radians, 0 = +X, π/2 = down) points out into open space. It fires at the
/// ship within [range] when it has line of sight and the ship is inside
/// ±[aimArc] of [facing]. Shells kill the ship and shove the cargo.
class TurretSpec extends ObstacleSpec {
  const TurretSpec(
    this.base, {
    required this.facing,
    this.range = 9,
    this.cooldown = 2.2,
    this.aimArc = 1.3,
    this.shellSpeed = 4.5,
    this.hp = 2,
    this.phase = 0,
  });
  final Pt base;
  final double facing;
  final double range;
  final double cooldown;
  final double aimArc;
  final double shellSpeed;
  final int hp;

  /// Seconds added to the first cooldown so turrets don't fire in unison.
  final double phase;
}

/// Facing shorthands for [TurretSpec.facing] (+Y is down).
const double kFaceUp = -math.pi / 2;
const double kFaceDown = math.pi / 2;
const double kFaceLeft = math.pi;
const double kFaceRight = 0;

/// Reactor core (Thrust's power plant). [disableHits] hits knock every
/// turret offline for [disableSeconds]; destroying it ([hp] hits) starts a
/// meltdown — deliver within [escapeSeconds] or the cave goes with it.
/// Only valid on levels flown by an armed ship.
class ReactorSpec extends ObstacleSpec {
  const ReactorSpec(
    this.center, {
    this.radius = 0.6,
    this.hp = 8,
    this.disableHits = 3,
    this.disableSeconds = 10,
    this.escapeSeconds = 30,
  });
  final Pt center;
  final double radius;
  final int hp;
  final int disableHits;
  final double disableSeconds;
  final double escapeSeconds;
}

// ── Pickups (fly-through sensors, ship only) ───────────────────────────────

sealed class PickupSpec {
  const PickupSpec();
  Pt get pos;
}

/// Fuel canister: flying through it adds [amount] units (capped at the tank).
class FuelCellSpec extends PickupSpec {
  const FuelCellSpec(this.pos, {this.amount = 25});
  @override
  final Pt pos;
  final double amount;
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
