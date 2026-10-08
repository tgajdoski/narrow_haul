import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  tearDown(() => FlightTuning.load());

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

    test('the fast speed builds up over boostBuildUp, then resets', () {
      var charge = 0.0;
      const dt = 1 / 60;
      final frames = (FlightTuning.boostBuildUp / dt).ceil();
      final shaped = FlightTuning.shapeStick(1, 2);
      expect(FlightTuning.applyBoostCharge(shaped, charge), 1);
      var prev = 1.0;
      for (var i = 0; i < frames; i++) {
        charge = FlightTuning.nextBoostCharge(charge, 1, dt);
        final y = FlightTuning.applyBoostCharge(shaped, charge);
        expect(y, greaterThanOrEqualTo(prev));
        prev = y;
      }
      expect(prev, closeTo(2, 1e-9));
      // A tenth of the build-up gives only ~3% of the extra speed.
      final early = FlightTuning.applyBoostCharge(shaped, 0.1);
      expect(early, lessThan(1.05));
      // Back inside the notch: precise at once, charge gone.
      expect(FlightTuning.nextBoostCharge(1, 0.3, dt), 0);
      expect(FlightTuning.applyBoostCharge(FlightTuning.shapeStick(0.3, 2), 1),
          lessThan(1));
    });

    test('Agile ignores the build-up', () {
      FlightTuning.steer = SteerMode.agile;
      expect(FlightTuning.applyBoostCharge(2, 0), 2);
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

    test('Classic has no boost, so it flies like the original stick', () {
      FlightTuning.steer = SteerMode.classic;
      expect(ship(kKestrel).maxRotateInput, 1);
      expect(FlightTuning.shapeStick(1, 2), 1);
      expect(FlightTuning.shapeStick(0.5, 2), 0.5);
      expect(FlightTuning.stickBoosting(0.9), isFalse);
    });
  });

  group('presets', () {
    test('Agile is proportional up to the boost', () {
      const m = SteerMode.agile;
      expect(FlightTuning.shapeStick(1, 2, m), closeTo(2, 1e-9));
      final half = (1 + FlightTuning.stickDeadzone) / 2;
      expect(FlightTuning.shapeStick(half, 2, m), closeTo(1, 1e-9));
    });

    test('only Smooth has inertia and a glide', () {
      for (final m in SteerMode.values) {
        expect(m.spinUp > 0, m == SteerMode.smooth, reason: m.name);
        expect(m.releaseDecay < 22, m == SteerMode.smooth, reason: m.name);
      }
    });

    test('Centred camera is the original camera', () {
      const c = CameraMode.centered;
      expect([c.lead, c.towZoomOut, c.zoomMul], [0, 0, 1]);
      for (final m in CameraMode.values) {
        expect(m.zoomMul, inInclusiveRange(0.8, 1.0));
        expect(m.towZoomOut, inInclusiveRange(0.0, 0.15));
      }
    });

    test('saved names load back; unknown or missing ones use the defaults', () {
      FlightTuning.load(steerName: 'smooth', cameraName: 'wide');
      expect(FlightTuning.steer, SteerMode.smooth);
      expect(FlightTuning.camera, CameraMode.wide);
      FlightTuning.load(steerName: 'bogus');
      expect(FlightTuning.steer, SteerMode.twoSpeed);
      expect(FlightTuning.camera, CameraMode.lookAhead);
    });
  });
}
