import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  group('ShipSpec', () {
    test('Kestrel equals the legacy hard-coded ship', () {
      expect(kKestrel.thrustForce, 5.1);
      expect(kKestrel.secondsPerFullRotation, 4.0);
      expect(kKestrel.maxFuel, 100);
      expect(kKestrel.fuelDrainPerSecond, 12);
      expect(kKestrel.density, 1.15);
      expect(kKestrel.linearDamping, 0.22);
      expect(kKestrel.noseLocalY, -0.51);
      expect(kKestrel.rearLocalY, 0.39);
      expect(kKestrel.rearHalfWidth, 0.315);
      expect(kKestrel.hookLocalY, -0.36);
      expect(kKestrel.hookRadius, 0.21);
      expect(kKestrel.ropeLengthMul, 1.0);
      // Validator clearance stays at the legacy −0.55 threshold.
      expect(kKestrel.circumradius + 0.04, closeTo(0.55, 1e-9));
    });

    test('unknown id falls back to Kestrel', () {
      expect(shipById(null), same(kKestrel));
      expect(shipById('nope'), same(kKestrel));
    });
  });

  group('FieldSampler', () {
    const g0 = 1.375;

    test('no fields → exactly base gravity everywhere', () {
      const s = FieldSampler(fields: [], g0: g0, gravityMul: 1.3);
      for (final p in [const Pt(0, 0), const Pt(12.5, -3), const Pt(40, 40)]) {
        final a = s.accelAt(p.x, p.y, t: 7);
        expect(a.x, 0);
        expect(a.y, g0 * 1.3);
      }
    });

    test('gravity zone replaces gravity inside and blends continuously', () {
      const s = FieldSampler(
        fields: [
          GravityZoneSpec(Pt(10, 10), halfW: 4, halfH: 4, gx: 0, gy: 0, feather: 1),
        ],
        g0: g0,
      );
      expect(s.accelAt(10, 10).y, 0); // deep inside: zero-g
      expect(s.accelAt(20, 10).y, g0); // outside: base
      expect(s.accelAt(13.5, 10).y, closeTo(g0 * 0.5, 1e-9)); // mid-feather

      // Continuity: no jump larger than the step across the edge.
      var prev = s.accelAt(4, 10).y;
      for (var x = 4.0; x <= 10; x += 0.01) {
        final y = s.accelAt(x, 10).y;
        expect((y - prev).abs(), lessThan(g0 * 0.02));
        prev = y;
      }
    });

    test('wind adds on top of gravity, cargo factor and gusts apply', () {
      const s = FieldSampler(
        fields: [
          WindZoneSpec(Pt(0, 0),
              halfW: 5, halfH: 5, ax: 0.5, ay: 0, feather: 0,
              gustAmp: 0.5, gustPeriod: 4, cargoFactor: 0.5),
        ],
        g0: g0,
      );
      final a = s.accelAt(0, 0, t: 0);
      expect(a.x, closeTo(0.5 * g0, 1e-9));
      expect(a.y, g0);
      expect(s.accelAt(0, 0, t: 1).x, closeTo(0.75 * g0, 1e-9)); // gust peak
      expect(s.accelAt(0, 0, cargo: true).x, closeTo(0.25 * g0, 1e-9));
    });

    test('gravity well pulls toward center and is capped', () {
      const s = FieldSampler(
        fields: [GravityWellSpec(Pt(0, 0), strength: 10, softening: 0.5, maxG: 2)],
        g0: g0,
        gravityMul: 0,
      );
      final right = s.accelAt(3, 0);
      expect(right.x, lessThan(0)); // pulled left, toward the well
      expect(right.x, closeTo(-10 / (9 + 0.25) * g0, 1e-9));
      final near = s.accelAt(0.1, 0);
      expect(near.x.abs(), closeTo(2 * g0, 1e-9)); // capped at maxG
    });
  });
}
