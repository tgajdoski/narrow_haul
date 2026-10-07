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
  });

  final String id;
  final String name;

  /// Sprite path relative to `assets/`.
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
const kKestrel = ShipSpec(id: 'kestrel', name: 'Kestrel');

const Map<String, ShipSpec> kShips = {
  'kestrel': kKestrel,
};

ShipSpec shipById(String? id) => kShips[id] ?? kKestrel;
