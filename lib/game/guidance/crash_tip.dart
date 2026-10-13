import 'dart:math' as math;

/// Why the ship was lost, from the moment it hit (pure Dart). The crash
/// screen turns it into one line of advice ([crashTip]), and `level_fail`
/// reports it.
enum CrashKind {
  /// The nose pointed down: thrust drove the ship into the rock.
  noseDown,

  /// Came down onto the floor too fast.
  hardLanding,

  /// Hit a wall or the ceiling too fast.
  wallHit,

  /// Touched moving machinery, a turret, a reactor or a well core (any
  /// touch is fatal).
  machinery,

  /// Hit by a turret shell.
  shot,

  /// The reactor meltdown ran out.
  meltdown,
}

/// Steeper than this (from local up) is a nose-down crash.
const double kNoseDownCrashTilt = 100;

/// Ground within this slope of level counts as a floor.
const double kFloorSlopeDeg = 40;

/// [cause] is `level_fail`'s (wall / shot / meltdown). [rock] is false for
/// machinery and other always-lethal walls. [tiltDeg] is the nose's angle
/// from local up at the hit, [groundCos] the cosine between the surface
/// normal and local up (1 = flat floor, −1 = ceiling).
CrashKind classifyCrash({
  required String cause,
  required bool rock,
  required double tiltDeg,
  required double groundCos,
}) {
  if (cause == 'shot') return CrashKind.shot;
  if (cause == 'meltdown') return CrashKind.meltdown;
  if (!rock) return CrashKind.machinery;
  if (tiltDeg > kNoseDownCrashTilt) return CrashKind.noseDown;
  if (groundCos >= math.cos(kFloorSlopeDeg * math.pi / 180)) {
    return CrashKind.hardLanding;
  }
  return CrashKind.wallHit;
}

/// One line of advice for the crash screen.
String crashTip(CrashKind kind) => switch (kind) {
      CrashKind.noseDown =>
        'The nose was pointing down, so the engine pushed you into the rock. '
            'Keep the nose within a quarter turn of up.',
      CrashKind.hardLanding =>
        'Came down too fast. Short taps of thrust slow the fall before the floor.',
      CrashKind.wallHit =>
        'Hit the rock too fast. Slow touches only scrape, so ease in near walls.',
      CrashKind.machinery =>
        'Moving machinery breaks the hull on any touch. Wait for the gap.',
      CrashKind.shot =>
        'A turret shell got you. Shoot first, or stay out of its sight line.',
      CrashKind.meltdown =>
        'The reactor blew. After a reactor kill, head for the pad straight away.',
    };
