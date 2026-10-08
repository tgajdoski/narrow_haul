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

  static const double turnMulMin = 0.75;
  static const double turnMulMax = 2.0;
  static const double spinUpMax = 0.12;

  /// The joystick's own dead zone (`_FloatingJoystick._deadzone`).
  static const double stickDeadzone = 0.06;

  static bool get isStock => turnMul == 1.0 && curveExpo == 0.0 && spinUp == 0.0;

  static void set({double? turn, double? expo, double? spin}) {
    if (turn != null) turnMul = turn.clamp(turnMulMin, turnMulMax);
    if (expo != null) curveExpo = expo.clamp(0.0, 1.0);
    if (spin != null) spinUp = spin.clamp(0.0, spinUpMax);
  }

  static void reset() => set(turn: 1.0, expo: 0.0, spin: 0.0);

  /// Shapes a raw stick axis (−1…1). With [expo] 0 this is the identity, so
  /// stock input is untouched. Otherwise the range past the dead zone is
  /// rescaled to 0…1 (no jump when the stick leaves the dead zone) and
  /// blended toward a cubic.
  static double shapeAxis(double x, {double? expo, double deadzone = stickDeadzone}) {
    final e = expo ?? curveExpo;
    if (e <= 0) return x.clamp(-1.0, 1.0);
    final a = x.abs();
    if (a <= deadzone) return 0;
    final t = math.min(1.0, (a - deadzone) / (1 - deadzone));
    return x.sign * ((1 - e) * t + e * t * t * t);
  }
}
