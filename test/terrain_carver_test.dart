import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/crate_spots.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/terrain_carver.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  final caves = <(CaveLevelDef, ShipSpec)>[
    for (int i = 0; i < LevelRegistry.totalLevels; i++)
      if (LevelRegistry.defAt(i) case final CaveLevelDef def)
        (def, LevelRegistry.shipFor(i)),
  ];
  final biggest = caves
      .map((c) => c.$1.spec)
      .reduce((a, b) => a.worldW * a.worldH >= b.worldW * b.worldH ? a : b);

  List<CarveGuard> guardsOf(LevelSpec s) => padGuards(
        shipSpawn: s.shipSpawn,
        goalCenter: s.goal.center,
        goalHalfW: s.goal.halfW,
        goalHalfH: s.goal.halfH,
      );

  // A rock point near the middle of the level, away from the pads.
  Pt rockPoint(BuiltCave cave, LevelSpec s) {
    for (double y = 2; y < s.worldH - 2; y += 0.5) {
      for (double x = 2; x < s.worldW - 2; x += 0.5) {
        if (cave.fieldAt(x, y) > 0.8) {
          final p = Pt(x, y);
          final far = [s.shipSpawn, s.goal.center].every(
              (a) => (a.x - x).abs() > 3 || (a.y - y).abs() > 3);
          if (far) return p;
        }
      }
    }
    throw StateError('no rock in ${s.id}');
  }

  test('a carve opens rock and leaves the cached cave untouched', () {
    final spec = caves.first.$1.spec;
    final cave = buildCave(spec);
    final before = List<List<Pt>>.from(cave.loops);
    final fieldCopy = List<double>.from(cave.field);
    final carver = TerrainCarver(cave, guards: guardsOf(spec));
    final p = rockPoint(cave, spec);
    expect(carver.fieldAt(p.x, p.y), greaterThan(0));
    expect(carver.carve(p.x, p.y, 1.2), isTrue);
    expect(carver.fieldAt(p.x, p.y), lessThan(0));
    expect(carver.dirty, isTrue);
    final loops = carver.extract();
    expect(loops, isNotEmpty);
    expect(carver.dirty, isFalse);
    expect(cave.field, fieldCopy, reason: 'memoized field mutated');
    expect(buildCave(spec).loops.length, before.length);
  });

  test('carving is deterministic', () {
    final spec = caves[3].$1.spec;
    final cave = buildCave(spec);
    final p = rockPoint(cave, spec);
    List<List<Pt>> run() {
      final c = TerrainCarver(cave, guards: guardsOf(spec))
        ..carve(p.x, p.y, 1.5)
        ..carve(p.x + 0.7, p.y, 0.8);
      return c.extract();
    }

    final a = run();
    final b = run();
    expect(a.length, b.length);
    for (int k = 0; k < a.length; k++) {
      expect(a[k].length, b[k].length);
    }
  });

  test('the world border and the pad floors never open', () {
    final spec = caves.first.$1.spec;
    final cave = buildCave(spec);
    final carver = TerrainCarver(cave, guards: guardsOf(spec));
    // Blast right at the corner and under both pads.
    carver
      ..carve(0.3, 0.3, 3)
      ..carve(spec.worldW - 0.3, spec.worldH - 0.3, 3)
      ..carve(spec.shipSpawn.x, spec.shipSpawn.y + 1.2, 2)
      ..carve(spec.goal.center.x, spec.goal.center.y + spec.goal.halfH + 0.8, 2);
    for (double t = 0; t <= 1; t += 0.05) {
      expect(carver.fieldAt(0.5, t * spec.worldH), greaterThan(0));
      expect(carver.fieldAt(t * spec.worldW, 0.5), greaterThan(0));
      expect(carver.fieldAt(spec.worldW - 0.5, t * spec.worldH), greaterThan(0));
    }
    // The pad floor's rock directly under each pad is untouched (sampled
    // inside the guard: bilinear lookups at its edge mix in outside cells).
    for (final g in guardsOf(spec)) {
      for (double y = g.y0 + 0.15; y <= g.y1 - 0.15; y += 0.1) {
        final x = (g.x0 + g.x1) / 2;
        expect(carver.fieldAt(x, y), closeTo(cave.fieldAt(x, y), 0.05),
            reason: 'guarded cell changed at ($x, $y)');
      }
    }
  });

  test('re-extracting the biggest level stays within a frame budget', () {
    final cave = buildCave(biggest);
    final carver = TerrainCarver(cave);
    final p = rockPoint(cave, biggest);
    carver.carve(p.x, p.y, 2);
    carver.extract(); // warm-up (JIT)
    final sw = Stopwatch()..start();
    const runs = 5;
    for (int k = 0; k < runs; k++) {
      carver.carve(p.x + k * 0.3, p.y, 1);
      carver.extract();
    }
    final ms = sw.elapsedMilliseconds / runs;
    // ignore: avoid_print
    print('re-extract ${biggest.id} (${biggest.worldW}×${biggest.worldH} m): '
        '${ms.toStringAsFixed(1)} ms');
    expect(ms, lessThan(60));
  });

  group('crate spots', () {
    for (final (def, ship) in caves) {
      if (ship.armed) continue;
      test(def.spec.id, () {
        final spec = def.spec;
        final spots = crateSpots(spec, ship: ship);
        expect(spots.length, greaterThanOrEqualTo(3),
            reason: '${spec.id}: only ${spots.length} crate spots');
        final cave = buildCave(spec);
        for (final p in spots) {
          expect(cave.fieldAt(p.x, p.y), lessThan(-ship.circumradius),
              reason: '${spec.id}: crate at (${p.x}, ${p.y}) in rock');
          for (final a in [spec.shipSpawn, spec.cargoSpawn, spec.goal.center]) {
            final d2 = (a.x - p.x) * (a.x - p.x) + (a.y - p.y) * (a.y - p.y);
            expect(d2, greaterThanOrEqualTo(kCrateAnchorClearance * kCrateAnchorClearance));
          }
        }
      });
    }
  });
}
