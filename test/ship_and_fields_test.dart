import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
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
      expect(kKestrel.rearLocalY, closeTo(0.39 * ShipSpec.hullGrowth, 1e-9));
      expect(kKestrel.hookRadius, 0.21);
      expect(kKestrel.ropeLengthMul, 1.0);
      // Flight mass is the original triangle hull's (base ±0.315 at +0.39,
      // nose −0.51), whatever the traced outline.
      expect(kKestrel.mass, closeTo(0.5 * 0.63 * 0.9 * 1.15, 1e-9));
    });

    test('hulls are traced from the art and stay inside the sprite', () {
      for (final s in kShips.values) {
        final r = s.spriteRect;
        final polys = s.hullPolygons;
        expect(polys, isNotEmpty, reason: s.id);
        for (final poly in polys) {
          expect(poly.length, inInclusiveRange(3, 8), reason: s.id);
          for (final (x, y) in poly) {
            expect(x, inInclusiveRange(r.left, r.right), reason: s.id);
            expect(y, inInclusiveRange(r.top, r.bottom), reason: s.id);
          }
        }
        // The base sits on the engine anchor, the nose tip is the hull's top.
        final ys = [for (final p in polys) for (final (_, y) in p) y];
        expect(ys.reduce((a, b) => a > b ? a : b), closeTo(s.rearLocalY, 1e-9), reason: s.id);
        expect(ys.reduce((a, b) => a < b ? a : b), closeTo(s.noseLocalY, 1e-9), reason: s.id);
        // Hook just behind the nose, inside the hull's reach.
        expect(s.hookLocalY, greaterThan(s.noseLocalY), reason: s.id);
        expect(s.circumradius, lessThan(0.85), reason: s.id);
        // Balance point of the legacy hull, above the base.
        expect(s.massCenterY, lessThan(s.rearLocalY), reason: s.id);
      }
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

  group('field guardrails', () {
    LevelSpec course(List<FieldSpec> fields) => LevelSpec(
          id: 'test_course',
          seed: 1,
          name: 'Test',
          themeId: 'ice',
          worldW: 34,
          worldH: 20,
          tunnels: const [
            TunnelSpec([Pt(5, 9), Pt(11, 8), Pt(17, 9), Pt(23, 8), Pt(29, 9)], width: 2.0),
            TunnelSpec([Pt(17, 9), Pt(17, 12.5)], width: 1.5),
          ],
          chambers: const [
            ChamberSpec(Pt(5, 9), 2.4),
            ChamberSpec(Pt(17, 13), 1.8),
            ChamberSpec(Pt(29, 9), 2.4),
          ],
          fields: fields,
          shipSpawn: const Pt(5, 9),
          cargoSpawn: const Pt(17, 13),
          goal: const GoalSpec(Pt(29, 10.2)),
        );

    test('baseline course is valid', () {
      expect(validateCaveSpec(course(const [])), isEmpty);
    });

    test('wind gusting past the readable cap is rejected', () {
      final issues = validateCaveSpec(course(const [
        WindZoneSpec(Pt(11, 8.5), halfW: 3, halfH: 3, ax: 0.8, ay: 0, gustAmp: 0.5),
      ]));
      expect(issues.any((i) => i.startsWith('WIND')), isTrue, reason: '$issues');
    });

    test('wind over the cargo pocket is rejected', () {
      final issues = validateCaveSpec(course(const [
        WindZoneSpec(Pt(17, 13), halfW: 3, halfH: 3, ax: 0.8, ay: 0, feather: 0.2),
      ]));
      expect(issues.any((i) => i.startsWith('FIELD: cargo')), isTrue, reason: '$issues');
    });

    test('sideways pull at the goal is rejected', () {
      final issues = validateCaveSpec(course(const [
        GravityZoneSpec(Pt(29, 9), halfW: 3, halfH: 3, gx: 1, gy: 0),
      ]));
      expect(issues.any((i) => i.startsWith('FIELD: goal')), isTrue, reason: '$issues');
    });

    test('zero-g at the goal is fine — you drift in', () {
      expect(
        validateCaveSpec(course(const [
          GravityZoneSpec(Pt(29, 9), halfW: 3, halfH: 3, gx: 0, gy: 0),
        ])),
        isEmpty,
      );
    });

    test('well core too close to the cargo is rejected', () {
      final issues = validateCaveSpec(course(const [
        GravityWellSpec(Pt(18.8, 13), strength: 1, coreRadius: 0.6),
      ]));
      expect(issues.any((i) => i.startsWith('WELL')), isTrue, reason: '$issues');
    });

    test('well pulling on free cargo needs the cargo lock', () {
      LevelSpec withWell({required bool clamped}) => LevelSpec(
            id: 'test_well',
            seed: 1,
            name: 'Test',
            themeId: 'ice',
            worldW: 34,
            worldH: 20,
            tunnels: const [
              TunnelSpec([Pt(5, 9), Pt(11, 8), Pt(17, 9), Pt(23, 8), Pt(29, 9)], width: 2.0),
              TunnelSpec([Pt(17, 9), Pt(17, 12.5)], width: 1.5),
            ],
            chambers: const [
              ChamberSpec(Pt(5, 9), 2.4),
              ChamberSpec(Pt(17, 13), 1.8),
              ChamberSpec(Pt(29, 9), 2.4),
            ],
            fields: const [GravityWellSpec(Pt(21, 13), strength: 20, coreRadius: 0.8)],
            cargoClamped: clamped,
            shipSpawn: const Pt(5, 9),
            cargoSpawn: const Pt(17, 13),
            goal: const GoalSpec(Pt(29, 10.2)),
          );
      final free = validateCaveSpec(withWell(clamped: false));
      expect(free.any((i) => i.startsWith('FIELD: cargo')), isTrue, reason: '$free');
      final locked = validateCaveSpec(withWell(clamped: true));
      expect(locked.where((i) => i.startsWith('FIELD: cargo')), isEmpty, reason: '$locked');
    });
  });
}
