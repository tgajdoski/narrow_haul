import 'dart:math' as math;

/// Steering and camera presets the player picks in Settings → Cockpit
/// ([steer] / [camera], loaded in `main.dart`). Pure Dart, no Flame imports.
///
/// Turn rates come from the ship: rotate input ±1 is
/// [ShipSpec.rotationSpeedRadPerSec] (precise: at ~90°/s a 0.15 s reaction
/// overshoots ~13°, fine for lining up thrust beside a wall), and up to
/// ±[ShipSpec.turnBoost] for flips (a Kestrel 180° in 1.0 s instead of
/// 2.0 s, falling ~0.7 m during it instead of ~2.75 m). The autopilot always
/// sends |input| ≤ 1, so the validator and 3★ calibration don't depend on
/// the preset.
enum SteerMode {
  /// The original stick: one speed, the ship's rate at full deflection.
  classic('Classic', 'One speed, full stick = ship turn rate'),

  /// Precise inner zone, boost past the gold notch on the dial.
  twoSpeed('Two-speed', 'Precise inside, fast past the gold notch'),

  /// Two-speed with thruster inertia: spins up and glides to a stop.
  smooth('Smooth', 'Two-speed with inertia, eases in and out'),

  /// Proportional over the whole throw up to the boost rate.
  agile('Agile', 'Fast everywhere: half stick = ship turn rate'),

  /// The nose turns toward wherever the stick points (screen directions).
  pointer('Point', 'The nose turns to where you point the stick');

  const SteerMode(this.label, this.blurb);
  final String label;
  final String blurb;

  bool get hasBoost => this != classic;

  /// Gold notch on the dial (a distinct precise zone).
  bool get hasZones => this == twoSpeed || this == smooth;

  /// The stick is a direction, not a left/right turn.
  bool get isPointer => this == pointer;

  /// Seconds from rest to full boosted rate (0 = instant).
  double get spinUp => this == smooth ? 0.18 : 0;

  /// Spin decay per second once the stick is released (higher = stops
  /// sooner): ~0.05 s to stop normally, ~0.25 s gliding in Smooth.
  double get releaseDecay => this == smooth ? 8 : 22;
}

enum CameraMode {
  /// The original camera: centred on the ship, same view while towing.
  centered('Centred', 'Locked on the ship', lead: 0, towZoomOut: 0, zoomMul: 1),

  /// Leads 0.4 s of velocity (1 m at a 2.5 m/s cruise, ~15% of a phone's
  /// half-height, capped at 2 m) and opens 12% while towing (~0.9 m more
  /// below the pod).
  lookAhead(
    'Look-ahead',
    'Leads where you fly, opens up while towing',
    lead: 0.4,
    towZoomOut: 0.12,
    zoomMul: 1,
  ),

  /// 15% further out at all times, a smaller lead.
  wide(
    'Wide',
    'See more of the cave, smaller ship',
    lead: 0.3,
    towZoomOut: 0.08,
    zoomMul: 0.85,
  );

  const CameraMode(
    this.label,
    this.blurb, {
    required this.lead,
    required this.towZoomOut,
    required this.zoomMul,
  });
  final String label;
  final String blurb;

  /// Seconds of the ship's velocity to lead by.
  final double lead;

  /// Zoom-out while towing, as a fraction of the normal zoom.
  final double towZoomOut;

  /// Normal zoom relative to the base zoom (< 1 = further out).
  final double zoomMul;
}

abstract final class FlightTuning {
  static SteerMode steer = SteerMode.twoSpeed;
  static CameraMode camera = CameraMode.lookAhead;

  static const cameraLeadMaxMeters = 2.0;

  /// The joystick's own dead zone (`_FloatingJoystick._deadzone`).
  static const double stickDeadzone = 0.06;

  /// Stick deflection (fraction of the 56 px throw) where the precise zone
  /// ends (~31 px) and where the boost is full (~42 px). The ramp between
  /// them avoids an instant jump in spin.
  static const double boostStart = 0.55;
  static const double boostFull = 0.75;

  /// Seconds held past the notch until the boost is full. It eases in
  /// (smoothstep), so a short push past the notch barely boosts and the
  /// switch never jolts; back inside the notch is precise again at once.
  static const double boostBuildUp = 0.4;

  /// Advances the boost charge (0…1) for one frame of stick input [x].
  static double nextBoostCharge(double charge, double x, double dt) =>
      stickBoosting(x) ? math.min(1.0, charge + dt / boostBuildUp) : 0.0;

  /// Scales the part of [shaped] input above ±1 by the eased [charge].
  /// Modes without a notch (Agile, Classic) are unaffected.
  static double applyBoostCharge(double shaped, double charge) {
    final a = shaped.abs();
    if (!steer.hasZones || a <= 1) return shaped;
    final eased = charge * charge * (3 - 2 * charge);
    return shaped.sign * (1 + (a - 1) * eased);
  }

  /// While towing only this share of the extra boost applies: a fast spin
  /// whips the winch anchor (ω × 0.39 m) and flings the pod.
  static const double towBoostShare = 0.5;

  /// Keyboard: a held turn key boosts after this long, over [keyBoostRamp].
  static const double keyBoostDelay = 0.3;
  static const double keyBoostRamp = 0.2;

  /// Restores saved preset names; unknown or missing ones keep the default.
  static void load({String? steerName, String? cameraName}) {
    steer = SteerMode.values.asNameMap()[steerName] ?? SteerMode.twoSpeed;
    camera = CameraMode.values.asNameMap()[cameraName] ?? CameraMode.lookAhead;
  }

  /// Maps a raw stick axis (−1…1, after the joystick's dead zone) to rotate
  /// input for [mode]: ±1 is the ship's rate, up to ±[boost].
  static double shapeStick(double x, double boost, [SteerMode? mode]) {
    final a = x.abs();
    if (a <= stickDeadzone) return 0;
    final span = (a - stickDeadzone) / (1 - stickDeadzone);
    switch (mode ?? steer) {
      case SteerMode.classic:
        return x.clamp(-1.0, 1.0);
      case SteerMode.pointer:
        return 0; // steered by direction, see [pointerAxis]
      case SteerMode.agile:
        return x.sign * math.min(1.0, span) * boost;
      case SteerMode.twoSpeed:
      case SteerMode.smooth:
        if (a <= boostStart) {
          return x.sign * (a - stickDeadzone) / (boostStart - stickDeadzone);
        }
        final t = math.min(1.0, (a - boostStart) / (boostFull - boostStart));
        return x.sign * (1 + (boost - 1) * t);
    }
  }

  /// Point-to-steer: below this stick deflection the ship holds its
  /// heading (a resting thumb doesn't spin it).
  static const double pointerMinStick = 0.3;

  /// Seconds the heading controller takes to close an error: 0.12 s turns
  /// a 20° error into a full boost and eases into the target without
  /// overshoot (rate falls in proportion as the nose comes round).
  static const double pointerResponse = 0.12;

  /// Rotate input that turns a ship at angle [shipAngle] (rad, 0 = nose up,
  /// clockwise) toward the stick direction ([x], [y], screen axes, y down).
  /// [baseRate] is the ship's turn rate at input 1 (rad/s).
  static double pointerAxis({
    required double x,
    required double y,
    required double shipAngle,
    required double baseRate,
    required double boost,
  }) {
    if (x * x + y * y < pointerMinStick * pointerMinStick) return 0;
    final target = math.atan2(x, -y);
    var diff = (target - shipAngle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    if (diff.abs() < 0.01) return 0;
    return (diff / (pointerResponse * baseRate)).clamp(-boost, boost);
  }

  /// Whether a raw stick deflection is past the gold notch (for the dial).
  static bool stickBoosting(double x) => steer.hasZones && x.abs() > boostStart;

  /// Keyboard rotate input for a turn key held [heldSeconds].
  static double keyAxis(double direction, double heldSeconds, double boost) {
    if (direction == 0) return 0;
    final t = ((heldSeconds - keyBoostDelay) / keyBoostRamp).clamp(0.0, 1.0);
    return direction * (1 + (boost - 1) * t);
  }

  /// The boost a ship actually gets: none in Classic, reduced while towing.
  static double effectiveBoost(double boost, {required bool towing}) {
    if (!steer.hasBoost) return 1;
    return towing ? 1 + (boost - 1) * towBoostShare : boost;
  }
}
