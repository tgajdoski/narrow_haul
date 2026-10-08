import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  tearDown(FlightTuning.reset);

  group('shapeAxis', () {
    test('stock curve leaves the stick untouched', () {
      expect(FlightTuning.isStock, isTrue);
      for (final x in [-1.0, -0.5, -0.07, 0.0, 0.07, 0.5, 1.0]) {
        expect(FlightTuning.shapeAxis(x), x);
      }
    });

    test('ends and centre are fixed, sign kept', () {
      for (final e in [0.25, 0.5, 1.0]) {
        expect(FlightTuning.shapeAxis(0, expo: e), 0);
        expect(FlightTuning.shapeAxis(1, expo: e), closeTo(1, 1e-9));
        expect(FlightTuning.shapeAxis(-1, expo: e), closeTo(-1, 1e-9));
        expect(FlightTuning.shapeAxis(-0.5, expo: e), -FlightTuning.shapeAxis(0.5, expo: e));
      }
    });

    test('no jump past the dead zone, monotonic', () {
      const dz = FlightTuning.stickDeadzone;
      expect(FlightTuning.shapeAxis(dz, expo: 0.5), 0);
      expect(FlightTuning.shapeAxis(dz + 0.01, expo: 0.5), lessThan(0.02));
      var prev = -1.0;
      for (var i = 0; i <= 100; i++) {
        final y = FlightTuning.shapeAxis(i / 100, expo: 0.6);
        expect(y, greaterThanOrEqualTo(prev));
        prev = y;
      }
    });

    test('more expo gives finer control near centre', () {
      expect(
        FlightTuning.shapeAxis(0.5, expo: 1),
        lessThan(FlightTuning.shapeAxis(0.5, expo: 0.3)),
      );
    });
  });

  group('ship turn rate', () {
    ShipBody ship(ShipSpec spec) =>
        ShipBody(initialPosition: Vector2.zero(), onWallHit: () {}, spec: spec);

    test('stock tuning keeps every spec rate', () {
      for (final spec in kShips.values) {
        expect(ship(spec).turnRate, spec.rotationSpeedRadPerSec);
      }
    });

    test('turnMul scales the rate and is clamped', () {
      FlightTuning.set(turn: 1.5);
      expect(ship(kKestrel).turnRate, closeTo(kKestrel.rotationSpeedRadPerSec * 1.5, 1e-9));
      FlightTuning.set(turn: 9);
      expect(FlightTuning.turnMul, FlightTuning.turnMulMax);
    });
  });
}
