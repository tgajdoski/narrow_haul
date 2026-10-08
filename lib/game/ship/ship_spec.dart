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
  });

  final String id;
  final String name;

  /// Sprite path relative to `assets/`: 256×256 PNG, transparent, top-down,
  /// nose up, framed like `ship.png` (hull in the upper ~70%, engine bell at
  /// bottom center). Missing → Kestrel art tinted with [tint].
  final String sprite;

  /// Uniform scale applied to the hull, hook and engine anchor geometry.
  final double hullScale;
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

  // ── Hull geometry at scale 1 (meters, nose at −Y) ──────────────────────
  static const double _noseY = -0.51;
  static const double _rearY = 0.39;
  static const double _rearHalfW = 0.315;
  static const double _hookY = -0.36;
  static const double _hookRadius = 0.21;

  double get noseLocalY => _noseY * hullScale;

  /// Local +Y anchor at engine bell (rope + plume).
  double get rearLocalY => _rearY * hullScale;
  double get rearHalfWidth => _rearHalfW * hullScale;
  double get hookLocalY => _hookY * hullScale;
  double get hookRadius => _hookRadius * hullScale;

  /// Largest distance from the body origin to a hull vertex — the ship's
  /// clearance radius for validation.
  double get circumradius =>
      math.max(-noseLocalY, math.sqrt(rearHalfWidth * rearHalfWidth + rearLocalY * rearLocalY));

  /// Triangle hull area (m²).
  double get hullArea => 0.5 * (2 * rearHalfWidth) * (rearLocalY - noseLocalY);

  double get mass => hullArea * density;

  double get rotationSpeedRadPerSec => (math.pi * 2) / secondsPerFullRotation;

  /// Seconds of continuous thrust on a full tank at drain multiplier 1.
  double get burnSeconds => maxFuel / fuelDrainPerSecond;

  /// Velocity budget of a full tank (m/s): how much "flying" it buys.
  double get deltaV => thrustForce / mass * burnSeconds;
}

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
);

/// Heavy lifter for strong gravity and heavy cargo: big engine and tank,
/// long winch, but a wide hull that turns slowly.
const kMule = ShipSpec(
  id: 'mule',
  name: 'Mule',
  sprite: 'ship_mule.png',
  hullScale: 1.1,
  density: 1.3,
  thrustForce: 8.0,
  secondsPerFullRotation: 5.5,
  turnBoost: 1.6,
  maxFuel: 150,
  linearDamping: 0.3,
  ropeLengthMul: 1.25,
  tint: 0x66FF9A3C,
  blurb: 'Heavy lifter. Big engine and tank, slow to turn.',
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
