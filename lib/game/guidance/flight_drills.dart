import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/geom.dart';

/// Flight drills, pure Dart: a few rings on the first tutorial level that
/// teach *how* to fly before the first tow (hold a hover, drift with a small
/// tilt, set down gently). They are guidance only: the win rule never waits
/// for them, and hooking the pod ends them.

/// What a ring asks for.
enum DrillKind {
  /// Stay inside for [DrillCourse.holdSeconds] (a hover).
  hold,

  /// Fly through it.
  reach,

  /// Come to rest inside it, upright.
  land,
}

class DrillStep {
  const DrillStep({
    required this.kind,
    required this.center,
    required this.radius,
    required this.label,
    required this.tower,
  });

  final DrillKind kind;

  /// World metres.
  final Pt center;
  final double radius;

  /// Caps tag on the ring ('HOLD HERE').
  final String label;

  /// TOWER's line when the step starts.
  final String tower;
}

/// The ship as the drills see it.
class DrillShip {
  const DrillShip({
    required this.pos,
    required this.speed,
    required this.tiltDeg,
    required this.launched,
  });
  final Pt pos;
  final double speed;

  /// Degrees between the nose and local up.
  final double tiltDeg;
  final bool launched;
}

/// What happened this step.
enum DrillEvent { stepDone, finished, skipped }

/// The current ring, for the HUD.
class DrillView {
  const DrillView({
    required this.kind,
    required this.center,
    required this.radius,
    required this.label,
    required this.progress,
    required this.inside,
    required this.number,
    required this.count,
  });
  final DrillKind kind;
  final Pt center;
  final double radius;
  final String label;

  /// 0–1 for hold / land; 0 for reach.
  final double progress;
  final bool inside;

  /// 1-based step number and the total.
  final int number;
  final int count;
}

class DrillCourse {
  /// Rings in order: the first is a hover, the last a landing, any between
  /// are fly-throughs. [start] skips steps already done (a retry).
  DrillCourse(List<Pt> points, {int start = 0})
      : steps = [
          for (final (i, p) in points.indexed)
            if (i == 0)
              DrillStep(
                kind: DrillKind.hold,
                center: p,
                radius: holdRadius,
                label: 'HOLD HERE',
                tower: 'Lift into the ring and hold her there. '
                    'Feather the thrust: short taps, not one long burn.',
              )
            else if (i == points.length - 1)
              DrillStep(
                kind: DrillKind.land,
                center: p,
                radius: landRadius,
                label: 'SET DOWN',
                tower: 'Now set her down in the ring. '
                    'Nose up, ease off, let her settle.',
              )
            else
              DrillStep(
                kind: DrillKind.reach,
                center: p,
                radius: reachRadius,
                label: 'FLY HERE',
                tower: 'Tilt a little toward the ring, not a lot. '
                    'Small tilt, small push. Level out to stop.',
              ),
        ],
        _index = start.clamp(0, points.length);

  static const double holdRadius = 1.5;
  static const double reachRadius = 1.5;
  static const double landRadius = 2.2;

  /// Seconds inside the hover ring.
  static const double holdSeconds = 1.0;

  /// Seconds at rest for a landing.
  static const double settleSeconds = 0.5;

  /// At rest: slower than this (m/s), and upright within this tilt.
  static const double restSpeed = 0.3;
  static const double restTilt = 35;

  /// Progress drains this much slower than it fills when the ship drifts
  /// out, so a wobble isn't a reset.
  static const double drainRate = 0.5;

  /// A step not done after this many seconds of flight ends the drills
  /// (gently: the pilot goes on to the pod).
  static const double stepTimeout = 25;

  final List<DrillStep> steps;
  int _index;
  double _progress = 0;
  double _stepTime = 0;
  bool _inside = false;
  bool _skipped = false;

  int get index => _index;
  bool get done => _index >= steps.length || _skipped;
  bool get skipped => _skipped;

  DrillStep? get current => done ? null : steps[_index];

  DrillView? get view {
    final s = current;
    if (s == null) return null;
    return DrillView(
      kind: s.kind,
      center: s.center,
      radius: s.radius,
      label: s.label,
      progress: _progress,
      inside: _inside,
      number: _index + 1,
      count: steps.length,
    );
  }

  /// Ends the drills (pod hooked, timed out).
  void skip() {
    if (!done) _skipped = true;
  }

  DrillEvent? update(double dt, DrillShip ship) {
    final s = current;
    if (s == null || !ship.launched) return null;
    _stepTime += dt;
    final dx = ship.pos.x - s.center.x;
    final dy = ship.pos.y - s.center.y;
    _inside = dx * dx + dy * dy <= s.radius * s.radius;
    switch (s.kind) {
      case DrillKind.hold:
        _fill(dt, _inside, holdSeconds);
      case DrillKind.reach:
        if (_inside) _progress = 1;
      case DrillKind.land:
        final atRest = _inside &&
            ship.speed <= restSpeed &&
            ship.tiltDeg <= restTilt;
        _fill(dt, atRest, settleSeconds);
    }
    if (_progress >= 1) {
      _index++;
      _progress = 0;
      _stepTime = 0;
      _inside = false;
      return done ? DrillEvent.finished : DrillEvent.stepDone;
    }
    if (_stepTime >= stepTimeout) {
      _skipped = true;
      return DrillEvent.skipped;
    }
    return null;
  }

  void _fill(double dt, bool on, double seconds) {
    _progress = on
        ? math.min(1, _progress + dt / seconds)
        : math.max(0, _progress - dt * drainRate / seconds);
  }
}
