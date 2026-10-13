import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/tilt_steer.dart';

const g = 9.81;
const dt = 1 / 60;

/// Accelerometer reading (up = +1 g) for a phone in landscape leaning
/// [deg] clockwise, on the side where device +x points up the screen
/// ([side] 1) or down (−1).
List<double> accelFor(double deg, {double side = 1, double upright = 1}) {
  final t = deg * math.pi / 180;
  final inPlane = g * upright;
  final z = g * math.sqrt(math.max(0, 1 - upright * upright));
  return [side * inPlane * math.cos(t), side * inPlane * math.sin(t), z];
}

void feed(TiltSteer t, double deg, {double side = 1, double upright = 1, int frames = 1, double gyroZ = 0}) {
  for (var i = 0; i < frames; i++) {
    final a = accelFor(deg, side: side, upright: upright);
    t.onAccel(a[0], a[1], a[2]);
    t.onGyro(0, 0, gyroZ);
    t.step(dt);
  }
}

void main() {
  test('reads a clockwise lean as positive on both landscape sides', () {
    for (final side in const [1.0, -1.0]) {
      final t = TiltSteer();
      final a = accelFor(15, side: side);
      t.onAccel(a[0], a[1], a[2]);
      expect(t.accelAngle * 180 / math.pi, closeTo(15, 1e-6), reason: 'side $side');
    }
  });

  test('a held lean is straight ahead after a recentre', () {
    final t = TiltSteer(mode: TiltMode.rate);
    feed(t, 12, frames: 5);
    expect(t.axis(2), 0);
    feed(t, 12, frames: 120);
    expect(t.axis(2), 0);
  });

  test('dead zone, precise range and boost ramp', () {
    final t = TiltSteer(mode: TiltMode.rate);
    feed(t, 0);
    feed(t, 2, frames: 300);
    expect(t.axis(2), 0, reason: 'inside the dead zone');
    feed(t, 0, frames: 300);
    t.recentre();
    feed(t, 0);
    feed(t, 9.5, frames: 300);
    expect(t.axis(2), closeTo(0.5, 0.02));
    feed(t, -15, frames: 300);
    expect(t.axis(2), closeTo(-1, 0.02));
    feed(t, 19.5, frames: 300);
    expect(t.axis(2), closeTo(1.5, 0.03));
    feed(t, 50, frames: 300);
    expect(t.axis(2), closeTo(2, 1e-6));
  });

  test('high sensitivity turns sooner', () {
    final normal = TiltSteer(mode: TiltMode.rate);
    final high = TiltSteer(sensitivity: TiltSensitivity.high, mode: TiltMode.rate);
    for (final t in [normal, high]) {
      feed(t, 0);
      feed(t, 10, frames: 300);
    }
    expect(high.axis(2), greaterThan(normal.axis(2)));
  });

  test('the gyro answers at once, the accelerometer cancels its drift', () {
    final t = TiltSteer();
    feed(t, 0, frames: 10);
    // A quick 20° clockwise turn in 0.1 s: the gyro leads the accelerometer.
    final rate = 20 * math.pi / 180 / 0.1;
    for (var i = 0; i < 6; i++) {
      t.onGyro(0, 0, -rate);
      t.step(dt);
    }
    expect(t.leanDeg, closeTo(20, 2.5));
    // A biased gyro at rest settles near the accelerometer's angle.
    final biased = TiltSteer();
    feed(biased, 0, frames: 2);
    feed(biased, 0, frames: 600, gyroZ: 0.02);
    expect(biased.leanDeg.abs(), lessThan(1));
  });

  test('a phone lying flat stops steering', () {
    final t = TiltSteer(mode: TiltMode.rate);
    feed(t, 0);
    feed(t, 25, frames: 300);
    expect(t.axis(2), greaterThan(1));
    feed(t, 25, upright: 0.2, frames: 10);
    expect(t.flat, isTrue);
    expect(t.axis(2), 0);
    expect((TiltSteer()..onAccel(0, 0, g)..step(dt)).targetHeading(), isNull);
  });

  test('the dial readout lines up with the stick zones', () {
    final t = TiltSteer(mode: TiltMode.rate);
    feed(t, 0);
    feed(t, 15, frames: 600);
    expect(
      t.dialX(stickDeadzone: 0.06, boostStart: 0.55, boostFull: 0.75),
      closeTo(0.55, 0.02),
    );
  });

  group('angle mode', () {
    double deg(double? rad) => rad! * 180 / math.pi;

    test('level is upright, a lean points the nose (× gain)', () {
      final t = TiltSteer();
      feed(t, 0);
      expect(t.targetHeading(), 0);
      feed(t, 0.8, frames: 300);
      expect(t.targetHeading(), 0, reason: 'tremor around level');
      // (the centre crept toward that 1° hold; start again from level)
      feed(t, 0, frames: 300);
      t.recentre();
      feed(t, 0);
      feed(t, 19, frames: 300);
      expect(deg(t.targetHeading()), closeTo(90, 1));
      feed(t, -10, frames: 300);
      expect(deg(t.targetHeading()), closeTo(-45, 1));
      feed(t, 45, frames: 300);
      expect(deg(t.targetHeading()), closeTo(TiltSteer.maxHeadingDeg, 1e-9));
    });

    test('aligning to the ship keeps the nose where it is', () {
      final t = TiltSteer();
      feed(t, 0);
      feed(t, 10, frames: 300);
      t.alignTo(-60 * math.pi / 180);
      feed(t, 10);
      expect(deg(t.targetHeading()), closeTo(-60, 0.5));
      // Leaning 6° further clockwise from there turns the nose 30°.
      feed(t, 16, frames: 300);
      expect(deg(t.targetHeading()), closeTo(-30, 1.5));
    });

    test('the heading controller turns the short way and rests on target', () {
      double axis(double target, double ship) => FlightTuning.headingAxis(
        target: target,
        shipAngle: ship,
        baseRate: math.pi / 2,
        boost: 2,
      );
      expect(axis(0.5, 0), 2);
      expect(axis(-3, 3), greaterThan(0), reason: 'across ±π the short way');
      expect(axis(1, 1), 0);
      expect(axis(0.01, 0), closeTo(0.01 / (FlightTuning.pointerResponse * math.pi / 2), 1e-9));
    });
  });
}
