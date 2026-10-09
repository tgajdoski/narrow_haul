import 'dart:math' as math;

/// Flight characteristics of one rocket. Pure const data (no Flame imports) so
/// the headless level validator can reason about clearance, lift and fuel.
///
/// Levels pick the ship (`LevelSpec.shipId` / `WorldDef.defaultShipId`), so a
/// level is always balanced and validated against exactly one ship.
class ShipSpec {
  const ShipSpec({
    required this.id,
    required this.name,
    this.sprite = 'ship.png',
    this.hullScale = 1.0,
    this.density = 1.15,
    this.thrustForce = 5.1,
    this.secondsPerFullRotation = 4.0,
    this.turnBoost = 2.0,
    this.maxFuel = 100,
    this.fuelDrainPerSecond = 12,
    this.linearDamping = 0.22,
    this.ropeLengthMul = 1.0,
    this.autoLevel = false,
    this.hoverAssist = false,
    this.armed = false,
    this.fireCooldown = 0.25,
    this.fuelPerShot = 0.6,
    this.muzzleSpeed = 9,
    this.tint,
    this.blurb = '',
    this.hull = kKestrelHull,
  });

  final String id;
  final String name;

  /// Sprite path relative to `assets/`: 256×256 PNG, transparent, top-down,
  /// nose up, framed like `ship.png` (hull in the upper ~70%, engine bell at
  /// bottom center). Missing → Kestrel art tinted with [tint].
  final String sprite;

  /// Uniform scale applied to the hull, hook, engine anchor and sprite.
  final double hullScale;

  /// Collision outline traced from this ship's sprite ([HullSection]s in
  /// sprite pixels; see [hullPolygons]).
  final List<HullSection> hull;
  final double density;

  /// Main engine strength (N), along local −Y.
  final double thrustForce;

  /// Seconds to complete one full 360° at rotate input 1 (the precise
  /// inner zone of the stick; what the autopilot and validator fly).
  final double secondsPerFullRotation;

  /// Turn-rate multiplier in the stick's boost zone (see `FlightTuning`).
  final double turnBoost;
  final double maxFuel;
  final double fuelDrainPerSecond;
  final double linearDamping;

  /// Multiplies the level's auto-computed rope max length (winch length).
  final double ropeLengthMul;

  /// Passive assist: ease toward "up" relative to local gravity when idle.
  final bool autoLevel;

  /// Passive assist: thrust partly cancels the local force field.
  final bool hoverAssist;

  /// Nose cannon: shows the FIRE button. Unarmed ships can only dodge turrets.
  final bool armed;

  /// Seconds between shots while FIRE is held.
  final double fireCooldown;

  /// Fuel units each shot costs — firing competes with flying for the tank.
  final double fuelPerShot;

  /// Shot speed (m/s) added to the ship's own velocity.
  final double muzzleSpeed;

  /// ARGB tint over the sprite (placeholder livery until bespoke art lands).
  final int? tint;

  /// One-line role description for UI.
  final String blurb;

  // ── Hull geometry (meters, nose at −Y) ────────────────────────────────
  // The collision hull is traced from the sprite ([hull]), so what you see
  // is what hits. Flight mass stays that of the original triangle hull
  // (nose −0.51, base ±0.315 at +0.39), so every ship flies as before.
  static const double _legacyNoseY = -0.51;
  static const double _rearY = 0.39;
  static const double _legacyRearHalfW = 0.315;
  static const double _hookRadius = 0.21;

  /// Size of the drawn ship and its hull relative to the first traced
  /// version (0.0068 m/px): big enough to read on a phone, with every cave
  /// level still passing the validator up to ×1.3. Mass and thrust don't
  /// depend on it.
  static const double hullGrowth = 1.6;

  /// Sprite scale at hull scale 1 (m per sprite pixel, both axes).
  static const double artMetersPerPx = 0.0068 * hullGrowth;

  /// Sprite pixel row of the engine nozzle line (every sprite is framed so).
  static const double artNozzleRow = 181;

  /// Sprite pixel column of the hull's centre line.
  static const double artCentreCol = 128;

  /// Meters per sprite pixel for this ship.
  double get artScale => artMetersPerPx * hullScale;

  /// The sprite's 256×256 rect in body space: the nozzle row sits on
  /// [rearLocalY] (plume and rope start there).
  ({double left, double top, double right, double bottom}) get spriteRect {
    final k = artScale;
    final top = rearLocalY - artNozzleRow * k;
    return (
      left: -artCentreCol * k,
      top: top,
      right: (256 - artCentreCol) * k,
      bottom: top + 256 * k,
    );
  }

  /// Convex collision polygons in body space (meters), one per [HullSection].
  List<List<(double, double)>> get hullPolygons {
    final k = artScale;
    return [
      for (final section in hull)
        [
          // Left edge top→bottom, then the right edge bottom→top (CCW on screen).
          for (final (y, hw) in section.rows)
            if (hw > 0) (-hw * k, rearLocalY + (y - artNozzleRow) * k)
            else (0.0, rearLocalY + (y - artNozzleRow) * k),
          for (final (y, hw) in section.rows.reversed)
            if (hw > 0) (hw * k, rearLocalY + (y - artNozzleRow) * k),
        ],
    ];
  }

  /// Tip of the hull's nose (local y, negative).
  double get noseLocalY =>
      rearLocalY + (hull.first.rows.first.$1 - artNozzleRow) * artScale;

  /// Local +Y anchor at engine bell (rope + plume).
  double get rearLocalY => _rearY * hullGrowth * hullScale;

  /// Nose hook: just behind the nose tip, where the pod is caught.
  double get hookLocalY => noseLocalY + 0.15 * hullScale;
  double get hookRadius => _hookRadius * hullScale;

  /// Largest distance from the body origin to a hull vertex — the ship's
  /// clearance radius for validation.
  double get circumradius {
    var r2 = 0.0;
    for (final poly in hullPolygons) {
      for (final (x, y) in poly) {
        r2 = math.max(r2, x * x + y * y);
      }
    }
    return math.sqrt(r2);
  }

  /// Area of the traced hull (m²).
  double get hullArea {
    var a = 0.0;
    for (final poly in hullPolygons) {
      for (var i = 0; i < poly.length; i++) {
        final (x0, y0) = poly[i];
        final (x1, y1) = poly[(i + 1) % poly.length];
        a += x0 * y1 - x1 * y0;
      }
    }
    return a.abs() / 2;
  }

  /// Flight mass (kg): the original triangle hull's, so swapping in the
  /// traced outline left thrust-to-weight and fuel use untouched.
  double get mass =>
      0.5 * (2 * _legacyRearHalfW) * (_rearY - _legacyNoseY) * hullScale * hullScale * density;

  /// Where the flight mass sits (local), as on the original triangle hull:
  /// its centroid. Keeps the ship's balance on its base as it was.
  double get massCenterY => (_legacyNoseY + 2 * _rearY) / 3 * hullGrowth * hullScale;

  /// Rotational inertia about [massCenterY] of the original triangle hull.
  double get massInertia {
    // Isosceles triangle, base b at the bottom, height h: about its centroid
    // I = m (b²/24 + h²/18).
    final b = 2 * _legacyRearHalfW * hullScale;
    final h = (_rearY - _legacyNoseY) * hullScale;
    return mass * (b * b / 24 + h * h / 18);
  }

  double get rotationSpeedRadPerSec => (math.pi * 2) / secondsPerFullRotation;

  /// Seconds of continuous thrust on a full tank at drain multiplier 1.
  double get burnSeconds => maxFuel / fuelDrainPerSecond;

  /// Velocity budget of a full tank (m/s): how much "flying" it buys.
  double get deltaV => thrustForce / mass * burnSeconds;
}

/// One convex piece of a hull: half-widths at sprite rows, top to bottom
/// (pixels of the 256×256 sprite; centre column 128, nozzle row 181). The
/// half-width must be a concave function of the row (≤ 4 rows) so the piece
/// is a convex polygon of ≤ 8 vertices, as Box2D needs. Traced a few pixels
/// inside the art, so the hitbox never sticks out of what's drawn.
class HullSection {
  const HullSection(this.rows);
  final List<(int, int)> rows;
}

/// ship.png: pointed nose, swept wings, small engine bell.
const kKestrelHull = [
  HullSection([(32, 0), (110, 40)]),
  HullSection([(112, 61), (138, 63), (156, 57), (181, 18)]),
];

/// ship_hopper.png: needle nose flaring into a wide flat stern.
const kHopperHull = [
  HullSection([(30, 0), (104, 27)]),
  HullSection([(104, 27), (140, 52)]),
  HullSection([(142, 66), (178, 67), (181, 60)]),
];

/// ship_mule.png: blunt nose, broad shoulders.
const kMuleHull = [
  HullSection([(40, 8), (60, 27), (116, 52)]),
  HullSection([(118, 66), (150, 67), (162, 62), (181, 18)]),
];

/// ship_skate.png: short nose, widest at the stern.
const kSkateHull = [
  HullSection([(60, 0), (66, 13), (90, 30), (130, 49)]),
  HullSection([(130, 49), (160, 64), (181, 67)]),
];

/// ship_vector.png: long wedge with stubby fins.
const kVectorHull = [
  HullSection([(30, 0), (100, 42)]),
  HullSection([(100, 42), (140, 64), (160, 67), (181, 44)]),
];

/// ship_talon.png: gun-barrel nose, wide wings.
const kTalonHull = [
  HullSection([(36, 0), (110, 38)]),
  HullSection([(112, 50), (150, 64), (166, 64), (181, 14)]),
];

/// Baseline rocket — exactly the pre-ShipSpec constants.
const kKestrel = ShipSpec(
  id: 'kestrel',
  name: 'Kestrel',
  blurb: 'Standard hauler. Balanced and forgiving.',
);

/// Light, twitchy scout for low-gravity caverns and tight squeezes: small
/// hull, snappy turns and punchy engine, but a small tank.
const kHopper = ShipSpec(
  id: 'hopper',
  name: 'Hopper',
  sprite: 'ship_hopper.png',
  hullScale: 0.8,
  thrustForce: 3.6,
  secondsPerFullRotation: 3.0,
  turnBoost: 2.0,
  maxFuel: 60,
  linearDamping: 0.18,
  tint: 0x6650FF9A,
  blurb: 'Light scout. Quick turns, small tank.',
  hull: kHopperHull,
);

/// Heavy lifter for strong gravity and heavy cargo: big engine and tank,
/// long winch, but a wide hull that turns slowly.
const kMule = ShipSpec(
  id: 'mule',
  name: 'Mule',
  sprite: 'ship_mule.png',
  // Kestrel-sized since hullGrowth 1.6 (its obstacle levels were built
  // around a smaller hull); the density keeps the 1.1-scale flight mass.
  density: 1.3 * 1.1 * 1.1,
  thrustForce: 8.0,
  secondsPerFullRotation: 5.5,
  turnBoost: 1.6,
  maxFuel: 150,
  linearDamping: 0.3,
  ropeLengthMul: 1.25,
  tint: 0x66FF9A3C,
  blurb: 'Heavy lifter. Big engine and tank, slow to turn.',
  hull: kMuleHull,
);

/// Stabilised all-rounder for wind and ice: steadier hull, and it rights
/// itself against local gravity whenever both controls are released.
const kSkate = ShipSpec(
  id: 'skate',
  name: 'Skate',
  sprite: 'ship_skate.png',
  thrustForce: 5.4,
  turnBoost: 1.8,
  linearDamping: 0.32,
  autoLevel: true,
  tint: 0x6699DDFF,
  blurb: 'Stabilised. Rights itself when you let go.',
  hull: kSkateHull,
);

/// Modern fly-by-wire hauler for zero-g and gravity wells: while the engine
/// burns, its computer cancels most of the local pull, so the ship goes where
/// it points. Lighter engine to compensate.
const kVector = ShipSpec(
  id: 'vector',
  name: 'Vector',
  sprite: 'ship_vector.png',
  thrustForce: 4.4,
  secondsPerFullRotation: 3.6,
  turnBoost: 2.0,
  maxFuel: 110,
  linearDamping: 0.35,
  hoverAssist: true,
  tint: 0x66C8A8FF,
  blurb: 'Fly-by-wire. Cancels gravity while thrusting.',
  hull: kVectorHull,
);

/// Armed escort hauler for defended caves: Kestrel handling, a nose cannon
/// to knock out turrets and reactor cores, and a slightly bigger tank to pay
/// for the shells.
const kTalon = ShipSpec(
  id: 'talon',
  name: 'Talon',
  sprite: 'ship_talon.png',
  maxFuel: 115,
  turnBoost: 2.2,
  armed: true,
  tint: 0x66FF5252,
  blurb: 'Armed escort. Nose cannon, shots cost fuel.',
  hull: kTalonHull,
);

const Map<String, ShipSpec> kShips = {
  'kestrel': kKestrel,
  'hopper': kHopper,
  'mule': kMule,
  'skate': kSkate,
  'vector': kVector,
  'talon': kTalon,
};

ShipSpec shipById(String? id) => kShips[id] ?? kKestrel;

/// A level validated for [native] stays geometrically flyable in any ship
/// whose hull is no larger. Lift and fuel still need checking per level.
bool shipFits(ShipSpec candidate, ShipSpec native) =>
    candidate.circumradius <= native.circumradius + 1e-9;

/// Ships the daily "Test Flight" may *consider* for a level's own [native]
/// (hull fits). Cave levels then re-validate each candidate; levels without
/// a validator also require [minDeltaVRatio] of the native ship's range.
List<ShipSpec> testFlightShips(ShipSpec native, {double minDeltaVRatio = 0}) => [
  for (final s in kShips.values)
    if (s.id != native.id &&
        shipFits(s, native) &&
        s.deltaV >= native.deltaV * minDeltaVRatio)
      s,
];
