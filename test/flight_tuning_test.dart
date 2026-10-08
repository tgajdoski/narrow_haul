import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  tearDown(FlightTuning.reset);

  group('two-speed stick', () {
    const start = FlightTuning.boostStart;
    const full = FlightTuning.boostFull;
    const dz = FlightTuning.stickDeadzone;

    test('precise zone is linear up to the ship rate', () {
      expect(FlightTuning.shapeStick(0, 2), 0);
      expect(FlightTuning.shapeStick(dz, 2), 0);
      expect(FlightTuning.shapeStick(start, 2), closeTo(1, 1e-9));
      final mid = (dz + start) / 2;
      expect(FlightTuning.shapeStick(mid, 2), closeTo(0.5, 1e-9));
      expect(FlightTuning.stickBoosting(start), isFalse);
    });

    test('boost zone ramps to the boost, sign kept', () {
      expect(FlightTuning.shapeStick(full, 2), closeTo(2, 1e-9));
      expect(FlightTuning.shapeStick(1, 2), closeTo(2, 1e-9));
      expect(FlightTuning.shapeStick(-1, 1.6), closeTo(-1.6, 1e-9));
      expect(FlightTuning.shapeStick((start + full) / 2, 2), closeTo(1.5, 1e-9));
      expect(FlightTuning.stickBoosting(start + 0.01), isTrue);
    });

    test('monotonic, no jump across the zones', () {
      var prev = 0.0;
      for (var i = 0; i <= 200; i++) {
        final y = FlightTuning.shapeStick(i / 200, 2.2);
        expect(y, greaterThanOrEqualTo(prev));
        expect(y - prev, lessThan(0.12));
        prev = y;
      }
    });

    test('a held key boosts after the delay', () {
      expect(FlightTuning.keyAxis(1, 0, 2), 1);
      expect(FlightTuning.keyAxis(-1, FlightTuning.keyBoostDelay, 2), -1);
      expect(FlightTuning.keyAxis(1, 2, 2), 2);
      expect(FlightTuning.keyAxis(0, 2, 2), 0);
    });

    test('towing trims the boost', () {
      expect(FlightTuning.effectiveBoost(2, towing: false), 2);
      expect(FlightTuning.effectiveBoost(2, towing: true), 1.5);
    });
  });

  group('ship turn rate', () {
    ShipBody ship(ShipSpec spec) =>
        ShipBody(initialPosition: Vector2.zero(), onWallHit: () {}, spec: spec);

    test('input 1 is the spec rate (autopilot and validator)', () {
      for (final spec in kShips.values) {
        expect(ship(spec).turnRate, spec.rotationSpeedRadPerSec);
      }
    });

    test('every ship boosts, the heavy Mule least', () {
      for (final spec in kShips.values) {
        expect(spec.turnBoost, greaterThan(1.4), reason: spec.id);
        expect(spec.turnBoost, lessThanOrEqualTo(kTalon.turnBoost));
      }
      expect(kMule.turnBoost, lessThan(kKestrel.turnBoost));
      final b = ship(kKestrel)..towing = true;
      expect(b.maxRotateInput, 1.5);
    });

    test('turnScale scales the rate and is clamped', () {
      FlightTuning.set(turn: 1.5);
      expect(ship(kKestrel).turnRate, closeTo(kKestrel.rotationSpeedRadPerSec * 1.5, 1e-9));
      FlightTuning.set(turn: 9);
      expect(FlightTuning.turnScale, FlightTuning.turnScaleMax);
    });
  });

  test('saved knobs load back, missing ones keep the shipped value', () {
    FlightTuning.set(turn: 1.3, lead: 0.2, towZoom: 0.05);
    final saved = FlightTuning.values;
    FlightTuning.reset();
    expect(FlightTuning.isShipped, isTrue);
    FlightTuning.load((k) => saved[k]);
    expect(FlightTuning.values, saved);
    FlightTuning.reset();
    FlightTuning.load((_) => null);
    expect(FlightTuning.isShipped, isTrue);
  });
}
