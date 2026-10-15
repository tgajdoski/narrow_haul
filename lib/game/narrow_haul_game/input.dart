part of '../narrow_haul_game.dart';

/// Flight input: touch HUD, keys and tilt combined into the ship's axes.
extension GameInput on NarrowHaulGame {
  /// Two-speed steering (see [FlightTuning]): ±1 is the ship's precise turn
  /// rate, the stick's outer zone or a held key boosts past it.
  void _combineInputs() {
    final boost = ship?.maxRotateInput ?? 1.0;
    final s = ship;
    // A pinch's fingers zoom, they don't steer.
    final touch = _pinch.active
        ? 0.0
        : FlightTuning.steer.isPointer
        ? (s == null
              ? 0.0
              : FlightTuning.pointerAxis(
                  x: _stickX,
                  y: _stickY,
                  shipAngle: s.body.angle,
                  baseRate: s.turnRate,
                  boost: boost,
                ))
        : FlightTuning.applyBoostCharge(
            FlightTuning.shapeStick(_touchAxis, boost),
            _boostCharge,
          );
    final key = FlightTuning.keyAxis(_keys.rotateAxis, _keyHeld, boost);
    final tilt = s == null ? 0.0 : _tiltAxis(s, boost);
    rotateAxis = (touch + key + tilt).clamp(-boost, boost);
    final boosting = rotateAxis.abs() > 1.001;
    if (boosting && !_wasBoosting && FlightTuning.steer.hasZones) {
      Haptics.light();
    }
    _wasBoosting = boosting;
    thrustHeld = _touchThrust || _keys.thrust;
    fireHeld = _touchFire || _keys.fire;
  }

  void _resetInputState() {
    rotateAxis = 0;
    _tiltFlatFor = 0;
    thrustHeld = false;
    fireHeld = false;
    _touchAxis = 0;
    _stickX = 0;
    _stickY = 0;
    _touchThrust = false;
    _touchFire = false;
    _keys.reset();
    _keyHeld = 0;
    _keyDir = 0;
    _wasBoosting = false;
    _boostCharge = 0;
    AudioService.stopEngine();
    AudioService.setAlarm(false);
    AudioService.setBuzz(false);
    AudioService.setSpores(false);
  }

  /// Advances the tilt filter: on the pad (or the hover before a
  /// continue) the way the phone is held becomes straight ahead.
  void _updateTilt(ShipBody s) {
    final t = _motion.steer
      ..sensitivity = FlightTuning.tiltSensitivity
      ..mode = FlightTuning.tiltMode;
    // On the pad, and while the stick or keys steer, the current hold
    // means the ship's current heading: letting go never jerks the nose.
    if (!s.launched || (t.mode == TiltMode.heading && _manualSteer)) {
      t.alignTo(s.body.angle);
    }
    t.step(_realDt);
    _tiltFlatFor = t.flat && s.launched ? _tiltFlatFor + _realDt : 0;
    if (_tiltFlatFor > 1) {
      _tiltFlatFor = double.negativeInfinity; // once per flight
      _comms?.say(
        const CommsLine(
          id: 'tilt_flat',
          callsign: 'TOWER',
          text: 'Hold the phone up like a wheel to steer by tilt.',
        ),
        expiresIn: NarrowHaulGame._commsHelpExpiry,
      );
    }
  }

  /// Stick or keys are steering (they override the tilt).
  bool get _manualSteer =>
      _touchAxis != 0 || _stickX != 0 || _stickY != 0 || _keys.rotateAxis != 0;

  /// The tilt's share of the rotate input. A lean never launches the ship:
  /// on the pad it only sets the centre.
  double _tiltAxis(ShipBody s, double boost) {
    if (!_motion.active || !s.launched) return 0;
    final t = _motion.steer;
    if (FlightTuning.tiltMode == TiltMode.rate) return t.axis(boost);
    if (_manualSteer) return 0;
    final target = t.targetHeading();
    if (target == null) return 0;
    // Crossed Wires negates the input after this: steer for the mirrored
    // heading so the controller stays stable (a negated one spins away).
    final m = _wiresCrossed ? -1.0 : 1.0;
    return m *
        FlightTuning.headingAxis(
          target: m * target,
          shipAngle: s.body.angle,
          baseRate: s.turnRate,
          boost: boost,
          tolerance: 0.03,
        );
  }

  /// Tapping the steering side in tilt mode: the current hold is the
  /// current heading (Angle) or straight ahead (Speed).
  void recentreTilt() {
    final s = ship;
    if (!_motion.active || s == null) return;
    _motion.steer.alignTo(s.body.angle);
    Haptics.light();
  }
}
