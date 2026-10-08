import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// Analytic obstacle motion, [t] = seconds since the obstacle was spawned.
/// Pure Dart: the runtime components track these paths, and the autopilot
/// flight test predicts them.

/// Pendulum bob centre.
Pt pendulumBobAt(PendulumSpec spec, double t) {
  final theta = spec.amplitudeRad * math.cos(2 * math.pi * t / spec.periodSec + spec.phase);
  return Pt(
    spec.pivot.x + spec.length * math.sin(theta),
    spec.pivot.y + spec.length * math.cos(theta),
  );
}

/// Sliding block centre (cosine ease between `from` and `to`).
Pt slidingBlockAt(SlidingBlockSpec spec, double t) {
  final s = 0.5 - 0.5 * math.cos(2 * math.pi * (t / spec.periodSec + spec.phase));
  return Pt(
    spec.from.x + (spec.to.x - spec.from.x) * s,
    spec.from.y + (spec.to.y - spec.from.y) * s,
  );
}
