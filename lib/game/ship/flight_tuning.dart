import 'dart:math' as math;

/// Handling and camera feel: the two-speed steering stick and the camera
/// lead / tow zoom. Pure Dart, no Flame imports. The defaults are the
/// shipped values; non-release builds can override them live (Settings →
/// Flight tuning, see `main.dart`).
///
/// Steering has two speeds. The inner part of the stick turns at the ship's
/// own rate ([ShipSpec.rotationSpeedRadPerSec]): at ~90°/s a 0.15 s reaction
/// overshoots ~13°, fine for lining up thrust beside a wall. Past
/// [boostStart] it ramps up to [ShipSpec.turnBoost] × that rate by
/// [boostFull], for flips: a Kestrel 180° takes 1.0 s instead of 2.0 s, and
/// falls ~0.7 m during it instead of ~2.75 m. Rotate input runs −boost…+boost;
/// ±1 is the ship's base rate, so the autopilot (always |input| ≤ 1), the
/// validator and the 3★ calibration are unchanged.
abstract final class FlightTuning {
  /// Scales every ship's turn rate, base and boost (dev only; 1 = shipped).
  static double turnScale = 1.0;

  /// Camera look-ahead: seconds of the ship's velocity to lead by, capped at
  /// [cameraLeadMaxMeters]. 0.4 s at a 2.5 m/s cruise leads 1 m (~15% of a
  /// phone's half-height at zoom 28), enough to see the next bend without
  /// pushing the ship toward the screen edge.
  static double cameraLead = defaultCameraLead;

  /// Zoom-out while towing, as a fraction of the normal zoom: 12% shows
  /// ~0.9 m more below the pod on a landscape phone.
  static double towZoomOut = defaultTowZoomOut;

  static const double defaultCameraLead = 0.4;
  static const double defaultTowZoomOut = 0.12;

  static const double cameraLeadMax = 0.8;
  static const double cameraLeadMaxMeters = 2.0;
  static const double towZoomOutMax = 0.25;
  static const double turnScaleMin = 0.75;
  static const double turnScaleMax = 2.0;

  /// The joystick's own dead zone (`_FloatingJoystick._deadzone`).
  static const double stickDeadzone = 0.06;

  /// Stick deflection (fraction of the 56 px throw) where the precise zone
  /// ends (~31 px) and where the boost is full (~42 px). The ramp between
  /// them avoids an instant jump in spin.
  static const double boostStart = 0.55;
  static const double boostFull = 0.75;

  /// While towing only this share of the extra boost applies: a fast spin
  /// whips the winch anchor (ω × 0.39 m) and flings the pod.
  static const double towBoostShare = 0.5;

  /// Keyboard: a held turn key boosts after this long, over [keyBoostRamp].
  static const double keyBoostDelay = 0.3;
  static const double keyBoostRamp = 0.2;

  static bool get isShipped =>
      turnScale == 1.0 &&
      cameraLead == defaultCameraLead &&
      towZoomOut == defaultTowZoomOut;

  static void set({double? turn, double? lead, double? towZoom}) {
    if (turn != null) turnScale = turn.clamp(turnScaleMin, turnScaleMax);
    if (lead != null) cameraLead = lead.clamp(0.0, cameraLeadMax);
    if (towZoom != null) towZoomOut = towZoom.clamp(0.0, towZoomOutMax);
  }

  /// Every knob by its save key (`dev_<key>` in ProgressService).
  static Map<String, double> get values => {
    'turn_scale': turnScale,
    'cam_lead': cameraLead,
    'tow_zoom_out': towZoomOut,
  };

  /// Restores knobs saved with [values]; missing ones keep the shipped value.
  static void load(double? Function(String key) read) => set(
    turn: read('turn_scale'),
    lead: read('cam_lead'),
    towZoom: read('tow_zoom_out'),
  );

  static void reset() =>
      set(turn: 1.0, lead: defaultCameraLead, towZoom: defaultTowZoomOut);

  /// Maps a raw stick axis (−1…1, after the joystick's dead zone) to rotate
  /// input: 0…1 linear across the precise zone, then a ramp to [boost].
  static double shapeStick(double x, double boost) {
    final a = x.abs();
    if (a <= stickDeadzone) return 0;
    if (a <= boostStart) {
      return x.sign * (a - stickDeadzone) / (boostStart - stickDeadzone);
    }
    final t = math.min(1.0, (a - boostStart) / (boostFull - boostStart));
    return x.sign * (1 + (boost - 1) * t);
  }

  /// Whether a raw stick deflection is in the boost zone (for the dial).
  static bool stickBoosting(double x) => x.abs() > boostStart;

  /// Keyboard rotate input for a turn key held [heldSeconds].
  static double keyAxis(double direction, double heldSeconds, double boost) {
    if (direction == 0) return 0;
    final t = ((heldSeconds - keyBoostDelay) / keyBoostRamp).clamp(0.0, 1.0);
    return direction * (1 + (boost - 1) * t);
  }

  /// The boost a ship actually gets: reduced while towing.
  static double effectiveBoost(double boost, {required bool towing}) =>
      towing ? 1 + (boost - 1) * towBoostShare : boost;
}
