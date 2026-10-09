/// Flutter-free physics constants shared by the game, the headless level
/// validator and `dart run` tools. Re-exported by `physics_constants.dart`.
library;

/// Base downward gravity (m/s² style scale in Forge2D units).
const double kGravityY = 1.375;

/// Combined (daily challenge × level) gravity multiplier is clamped to this so
/// stacked modifiers can never make a level unflyable.
const double kMaxGravityMul = 2.5;

/// Heaviest daily-challenge gravity preset ("Heavy Haul").
const double kMaxChallengeGravityMul = 1.8;

/// Size of the pod relative to the original (r 0.093 m), grown to read next
/// to the bigger ship (`ShipSpec.hullGrowth`). Art and collision grow
/// together; the density shrinks by growth², so its mass is unchanged.
const double kCargoGrowth = 3.0;

/// Cargo pod: circle radius (m) and base density (× level cargoDensityMul).
const double kCargoRadius = 0.14 * (2.0 / 3.0) * kCargoGrowth;
const double kCargoDensity = 2.0 / (kCargoGrowth * kCargoGrowth);

/// Delivery pads: cave levels lay a flat rock shelf this far below the drawn
/// pad box, and the win sensors reach [kPadSensorDrop] below it, so a ship or
/// a pod *resting* on the floor overlaps them by a solid margin.
const double kPadFloorDrop = 0.3;
const double kPadSensorDrop = 0.45;
