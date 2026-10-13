import 'dart:math' as math;

/// What a lean does.
enum TiltMode {
  /// The nose follows the phone: lean 7° and the ship points 30°, 19° and
  /// it points 90° (Normal). Small leans, so the screen stays readable;
  /// level phone = upright ship. Nothing to stop.
  heading('Angle', "The nose follows the phone's lean"),

  /// The lean sets the turn rate, like the stick (no spring back, so the
  /// pilot has to level the phone to stop turning).
  rate('Speed', 'Lean to turn, like the stick');

  const TiltMode(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// How far the phone must lean.
enum TiltSensitivity {
  low('Low', 'Lean further to turn', 1.3, 3.75),
  normal('Normal', 'A small lean turns the nose', 1.0, 5.0),
  high('High', 'The slightest lean turns it', 0.75, 6.5);

  const TiltSensitivity(this.label, this.blurb, this.angleScale, this.headingGain);
  final String label;
  final String blurb;

  /// Multiplies every lean angle of [TiltMode.rate].
  final double angleScale;

  /// Nose angle per degree of lean in [TiltMode.heading].
  final double headingGain;
}

/// Tilt steering: the phone held in landscape is a steering wheel. Leaning
/// it clockwise (right side down) turns the ship clockwise, at a rate set
/// by how far it leans, like the stick: a small lean is the precise rate,
/// past [boostStartDeg] it ramps to the ship's fast turn.
///
/// Pure Dart. Feed it raw sensor samples ([onAccel], [onGyro], device axes
/// as reported by `sensors_plus`: x right and y up of the portrait screen,
/// z out of it; the accelerometer reads +1 g *up*) and call [step] once per
/// game frame.
class TiltSteer {
  TiltSteer({this.sensitivity = TiltSensitivity.normal, this.mode = TiltMode.heading});

  TiltSensitivity sensitivity;
  TiltMode mode;

  /// [TiltMode.rate]: lean (degrees, × [TiltSensitivity.angleScale]) below
  /// which the ship doesn't turn, where the precise rate is full, and where
  /// the boost is. Kept small: a wrist can't lean far and still see the
  /// screen.
  static const double deadZoneDeg = 4;
  static const double boostStartDeg = 15;
  static const double boostFullDeg = 24;

  /// [TiltMode.heading]: lean ignored around level (hand tremor), and the
  /// furthest the nose is held from upright.
  static const double headingDeadZoneDeg = 1.0;
  static const double maxHeadingDeg = 175;

  /// Seconds the accelerometer takes to pull the gyro estimate back
  /// (complementary filter). Without a gyro the accelerometer is the only
  /// source and is just smoothed over [accelOnlyTau].
  static const double fusionTau = 0.5;
  static const double accelOnlyTau = 0.08;

  /// While the lean sits in the dead zone the centre creeps toward it over
  /// this many seconds, following a slowly changing grip.
  static const double neutralCreepTau = 3;

  /// In-screen-plane gravity (fraction of 1 g) below which the phone is
  /// lying too flat to read a lean: the output fades out between the two.
  static const double flatBelow = 0.35;
  static const double uprightAbove = 0.55;

  static const double _g = 9.81;

  // Latest samples.
  double _ax = 0, _ay = 0;
  bool _hasAccel = false;
  double _gyroZ = 0;
  bool _hasGyro = false;

  /// +1 when device +x points up the landscape screen, −1 when it points
  /// down (the other landscape side). Sticky so a big lean doesn't flip it.
  double _side = 1;

  /// Fused wheel angle (rad, clockwise positive) and the centre.
  double _angle = 0;
  bool _angleSet = false;
  double _neutral = 0;

  /// Ship angle (rad) the current hold should mean on the next [step]
  /// (0 = level = straight ahead / upright); null = keep the centre.
  double? _align = 0;

  /// 0 (lying flat) … 1 (upright enough to read a lean).
  double upright = 0;

  bool get hasSensor => _hasAccel;

  /// True while the phone is too flat for tilt steering.
  bool get flat => _hasAccel && upright < 0.5;

  /// Lean from the centre, in degrees (clockwise positive).
  double get leanDeg => (_angle - _neutral) * 180 / math.pi;

  void onAccel(double x, double y, double z) {
    _ax = x;
    _ay = y;
    _hasAccel = true;
    // Pick the landscape side only when it's clear (tilted < ~55°).
    if (_ax * _side < -0.6 * _g) _side = -_side;
  }

  void onGyro(double x, double y, double z) {
    _gyroZ = z;
    _hasGyro = true;
  }

  /// The current hold becomes straight ahead (upright) on the next [step].
  void recentre() => _align = 0;

  /// [TiltMode.heading]: the current hold becomes [shipAngle] (rad, 0 =
  /// upright, clockwise), so taking over from the stick doesn't jerk the
  /// nose. In [TiltMode.rate] it's a plain [recentre].
  void alignTo(double shipAngle) => _align = mode == TiltMode.heading ? shipAngle : 0;

  /// Forgets everything (new flight, sensors restarted).
  void reset() {
    _hasAccel = false;
    _hasGyro = false;
    _gyroZ = 0;
    _angleSet = false;
    _align = 0;
    upright = 0;
  }

  /// Wheel angle the accelerometer alone reads (rad, clockwise positive).
  double get accelAngle {
    // Screen up is _side·x, screen right is −_side·y; a clockwise lean
    // swings world-up toward screen left.
    return math.atan2(_side * _ay, _side * _ax);
  }

  /// Advances the filter by [dt] seconds.
  void step(double dt) {
    if (!_hasAccel) return;
    final inPlane = math.sqrt(_ax * _ax + _ay * _ay) / _g;
    upright = ((inPlane - flatBelow) / (uprightAbove - flatBelow)).clamp(0.0, 1.0);
    final measured = accelAngle;
    if (!_angleSet) {
      _angle = measured;
      _angleSet = true;
    } else {
      // Gyro z is counter-clockwise positive (right-hand rule, z out of
      // the screen), the same on either landscape side.
      if (_hasGyro) _angle -= _gyroZ * dt;
      final tau = _hasGyro ? fusionTau : accelOnlyTau;
      // Lying flat the accelerometer angle is noise: trust the gyro.
      final k = (1 - math.exp(-dt / tau)) * upright;
      _angle += _wrap(measured - _angle) * k;
      _angle = _wrap(_angle);
    }
    final align = _align;
    if (align != null) {
      // Invert [targetHeading]: the lean that maps to this ship angle.
      final maxRad = maxHeadingDeg * math.pi / 180;
      final a = _wrap(align).clamp(-maxRad, maxRad);
      final lean = a == 0
          ? 0.0
          : a / sensitivity.headingGain + a.sign * headingDeadZoneDeg * math.pi / 180;
      _neutral = _angle - lean;
      _align = null;
    } else if (leanDeg.abs() <
        (mode == TiltMode.heading
            ? headingDeadZoneDeg
            : deadZoneDeg * sensitivity.angleScale)) {
      _neutral += _wrap(_angle - _neutral) * (1 - math.exp(-dt / neutralCreepTau));
    }
  }

  /// [TiltMode.heading]: where the nose should point (rad, 0 = up,
  /// clockwise); null while the phone lies flat or before a sample.
  double? targetHeading() {
    if (!_hasAccel || upright < 0.5) return null;
    final lean = leanDeg;
    final past = lean.abs() - headingDeadZoneDeg;
    if (past <= 0) return 0;
    final deg = math.min(maxHeadingDeg, past * sensitivity.headingGain);
    return lean.sign * deg * math.pi / 180;
  }

  /// [TiltMode.rate]: rotate input (±1 = the ship's turn rate, up to
  /// ±[boost]).
  double axis(double boost) {
    if (!_hasAccel) return 0;
    final s = sensitivity.angleScale;
    final lean = leanDeg;
    final a = lean.abs();
    final dead = deadZoneDeg * s, start = boostStartDeg * s, full = boostFullDeg * s;
    if (a <= dead) return 0;
    final double v;
    if (a <= start) {
      v = (a - dead) / (start - dead);
    } else {
      v = 1 + (boost - 1) * math.min(1.0, (a - start) / (full - start));
    }
    return lean.sign * v * upright;
  }

  /// The lean as a stick deflection for the dial readout: the dead zone,
  /// precise range and boost line up with the stick's own zones.
  double dialX({
    required double stickDeadzone,
    required double boostStart,
    required double boostFull,
  }) {
    if (!_hasAccel) return 0;
    final s = sensitivity.angleScale;
    final lean = leanDeg;
    final a = lean.abs();
    final dead = deadZoneDeg * s, start = boostStartDeg * s, full = boostFullDeg * s;
    if (a <= dead) return 0;
    double x;
    if (a <= start) {
      x = stickDeadzone + (boostStart - stickDeadzone) * (a - dead) / (start - dead);
    } else if (a <= full) {
      x = boostStart + (boostFull - boostStart) * (a - start) / (full - start);
    } else {
      x = math.min(1.0, boostFull + (1 - boostFull) * (a - full) / full);
    }
    return lean.sign * x * upright;
  }

  static double _wrap(double a) {
    var r = (a + math.pi) % (2 * math.pi);
    if (r < 0) r += 2 * math.pi;
    return r - math.pi;
  }
}
