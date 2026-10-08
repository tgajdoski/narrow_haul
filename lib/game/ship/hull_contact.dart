import 'dart:math' as math;

/// What a ship touching static rock ([RockTag]) means. Pure Dart, no Flame
/// imports. Moving obstacles, turrets, reactors and well cores are plain
/// [WallTag]s and stay lethal at any speed.
enum HullContact {
  /// A slow touch at any angle: sparks, the ship slides or bounces off.
  scrape,

  /// Upright on its base on fairly flat ground: the ship rests there.
  touchdown,

  /// Too fast: the run ends as before.
  crash,
}

/// Fastest approach (m/s, the velocity component into the rock) that only
/// scrapes. 0.55 m/s is a slow drift into a wall; a 2.5 m/s cruise
/// clipping a wall at more than ~13° is still a crash. Sliding along a
/// wall is free (only the normal component counts).
const double kScrapeMaxSpeed = 0.55;

/// Fastest approach for a touchdown: 1.0 m/s is a drop from ~0.36 m at
/// 1 g (v² = 2gh, g = 1.375 m/s²), a firm but controlled landing.
const double kTouchdownMaxSpeed = 1.0;

/// The ship's nose must point within this of "up" for a touchdown...
const double kTouchdownMaxTilt = 35 * math.pi / 180;

/// ...and the ground must face within this of "up".
const double kTouchdownMaxSlope = 40 * math.pi / 180;

/// Classifies a rock contact.
///
/// [approachSpeed]: the ship's velocity into the rock (m/s, ≤ 0 = moving
/// away). [onBase]: the contact is on the hull's base (where the engine
/// bell sits), not the nose or flanks. [tiltCos]: cosine between the ship's
/// nose and local "up". [groundCos]: cosine between the rock's surface
/// normal and local "up".
HullContact classifyHullContact({
  required double approachSpeed,
  required bool onBase,
  required double tiltCos,
  required double groundCos,
}) {
  final upright =
      onBase &&
      tiltCos >= math.cos(kTouchdownMaxTilt) &&
      groundCos >= math.cos(kTouchdownMaxSlope);
  if (upright && approachSpeed <= kTouchdownMaxSpeed) {
    return HullContact.touchdown;
  }
  if (approachSpeed <= kScrapeMaxSpeed) return HullContact.scrape;
  return HullContact.crash;
}
