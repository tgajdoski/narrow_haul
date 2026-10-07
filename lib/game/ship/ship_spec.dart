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
    this.maxFuel = 100,
    this.fuelDrainPerSecond = 12,
    this.linearDamping = 0.22,
    this.ropeLengthMul = 1.0,
    this.autoLevel = false,
    this.hoverAssist = false,
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

  /// Seconds to complete one full 360° at full rotate input.
  final double secondsPerFullRotation;
  final double maxFuel;
  final double fuelDrainPerSecond;
  final double linearDamping;

  /// Multiplies the level's auto-computed rope max length (winch length).
  final double ropeLengthMul;

  /// Passive assist: ease toward "up" relative to local gravity when idle.
  final bool autoLevel;

  /// Passive assist: thrust partly cancels the local force field.
  final bool hoverAssist;

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
  linearDamping: 0.32,
  autoLevel: true,
  tint: 0x6699DDFF,
  blurb: 'Stabilised. Rights itself when you let go.',
);

const Map<String, ShipSpec> kShips = {
  'kestrel': kKestrel,
  'hopper': kHopper,
  'mule': kMule,
  'skate': kSkate,
};

ShipSpec shipById(String? id) => kShips[id] ?? kKestrel;
