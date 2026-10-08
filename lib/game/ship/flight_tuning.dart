import 'dart:math' as math;

/// Dev-only handling knobs for tuning the feel on a phone (Settings → Flight
/// tuning in non-release builds, see `main.dart`). Pure Dart, no Flame
/// imports. Every default equals stock behaviour, so tests, the autopilot
/// and release builds fly exactly as the [ShipSpec] says until the chosen
/// numbers are baked into the specs.
abstract final class FlightTuning {
  /// Multiplies every ship's turn rate ([ShipSpec.rotationSpeedRadPerSec]).
  static double turnMul = 1.0;

  /// Stick response curve: 0 = linear, 1 = cubic (precise near centre,
  /// full rate only at full deflection). Touch joystick only.
  static double curveExpo = 0.0;

  /// Seconds to reach full turn rate from rest (0 = instant, as stock).
  static double spinUp = 0.0;

  /// Fraction of the joystick's throw that gives full turn rate (1 = the
  /// whole 56 px, as stock; 0.45 ≈ 25 px). Touch joystick only.
  static double stickReach = 1.0;

  /// Camera look-ahead: seconds of the ship's velocity to lead by (0 =
  /// centred on the ship, as stock), capped at [cameraLeadMaxMeters].
  static double cameraLead = 0.0;

  /// Zoom-out while towing, as a fraction of the normal zoom (0 = none).
  static double towZoomOut = 0.0;

  static const double cameraLeadMax = 0.8;
  static const double cameraLeadMaxMeters = 2.5;
  static const double towZoomOutMax = 0.25;

  static const double turnMulMin = 0.75;
  static const double turnMulMax = 3.0;
  static const double spinUpMax = 0.12;
  static const double stickReachMin = 0.35;

  /// The joystick's own dead zone (`_FloatingJoystick._deadzone`).
  static const double stickDeadzone = 0.06;

  static bool get isStock =>
      turnMul == 1.0 &&
      curveExpo == 0.0 &&
      spinUp == 0.0 &&
      stickReach == 1.0 &&
      cameraLead == 0.0 &&
      towZoomOut == 0.0;

  static void set({
    double? turn,
    double? expo,
    double? spin,
    double? reach,
    double? lead,
    double? towZoom,
  }) {
    if (turn != null) turnMul = turn.clamp(turnMulMin, turnMulMax);
    if (expo != null) curveExpo = expo.clamp(0.0, 1.0);
    if (spin != null) spinUp = spin.clamp(0.0, spinUpMax);
    if (reach != null) stickReach = reach.clamp(stickReachMin, 1.0);
    if (lead != null) cameraLead = lead.clamp(0.0, cameraLeadMax);
    if (towZoom != null) towZoomOut = towZoom.clamp(0.0, towZoomOutMax);
  }

  /// Every knob by its save key (`dev_<key>` in ProgressService).
  static Map<String, double> get values => {
    'turn_mul': turnMul,
    'curve_expo': curveExpo,
    'spin_up': spinUp,
    'stick_reach': stickReach,
    'camera_lead': cameraLead,
    'tow_zoom': towZoomOut,
  };

  /// Restores knobs saved with [values]; missing ones stay stock.
  static void load(double? Function(String key) read) => set(
    turn: read('turn_mul'),
    expo: read('curve_expo'),
    spin: read('spin_up'),
    reach: read('stick_reach'),
    lead: read('camera_lead'),
    towZoom: read('tow_zoom'),
  );

  static void reset() =>
      set(turn: 1.0, expo: 0.0, spin: 0.0, reach: 1.0, lead: 0.0, towZoom: 0.0);

  /// Shapes a raw stick axis (−1…1). With [expo] 0 and [reach] 1 this is the
  /// identity, so stock input is untouched. [reach] < 1 hits full deflection
  /// sooner; otherwise the range past the dead zone is rescaled to 0…1 (no
  /// jump when the stick leaves the dead zone) and blended toward a cubic.
  static double shapeAxis(
    double x, {
    double? expo,
    double? reach,
    double deadzone = stickDeadzone,
  }) {
    final e = expo ?? curveExpo;
    final r = reach ?? stickReach;
    if (e <= 0 && r >= 1) return x.clamp(-1.0, 1.0);
    final a = x.abs();
    if (a <= deadzone) return 0;
    final span = math.max(1e-3, r - deadzone);
    final t = math.min(1.0, (a - deadzone) / span);
    return x.sign * ((1 - e) * t + e * t * t * t);
  }
}
