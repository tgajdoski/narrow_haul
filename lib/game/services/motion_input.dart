import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/tilt_steer.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';

/// Feeds the phone's accelerometer and gyroscope into a [TiltSteer], only
/// while [setActive] says a tilt-steered flight is live (sensors cost
/// battery). Android and iOS only; elsewhere it stays silent and the
/// steer reads 0.
class MotionInput {
  final TiltSteer steer = TiltSteer();

  StreamSubscription<AccelerometerEvent>? _accel;
  StreamSubscription<GyroscopeEvent>? _gyro;
  bool _active = false;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// False once [probe] found no accelerometer on this phone: tilt
  /// steering is then off and hidden, and the joystick steers.
  static bool available = supported;

  /// Listens for one accelerometer sample (app start). No sample within
  /// [timeout], or an error, marks the sensor [available] = false.
  static Future<bool> probe({Duration timeout = const Duration(seconds: 3)}) async {
    if (!supported) return available = false;
    try {
      await accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .first
          .timeout(timeout);
      return available = true;
    } catch (_) {
      return available = false;
    }
  }

  bool get active => _active;

  void setActive(bool on) {
    if (on == _active) return;
    _active = on;
    if (on) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    steer.reset();
    if (!supported) return;
    try {
      _accel = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) => steer.onAccel(e.x, e.y, e.z), onError: _onAccelError, cancelOnError: true);
      _gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) => steer.onGyro(e.x, e.y, e.z), onError: _onError, cancelOnError: true);
    } catch (e, st) {
      _onError(e, st);
    }
  }

  void _stop() {
    unawaited(_accel?.cancel());
    unawaited(_gyro?.cancel());
    _accel = null;
    _gyro = null;
  }

  // No accelerometer: tilt can't steer at all, so the joystick takes over
  // for the rest of the session (the saved choice is kept).
  void _onAccelError(Object e, [StackTrace? st]) {
    available = false;
    FlightTuning.tilt = false;
    _onError(e, st);
  }

  // A phone without a gyroscope errors that stream only; the accelerometer
  // still steers ([TiltSteer] falls back to it alone).
  void _onError(Object e, [StackTrace? st]) {
    ErrorReporter.report(e, st ?? StackTrace.current, context: 'MotionInput');
  }
}
