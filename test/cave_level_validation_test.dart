import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'helpers/caves.dart';

void main() {
  setUpAll(prebuildAllCaves);

  test('cave worlds: 8 missions each, Redoubt 5 (+ type ratings), unique ids', () {
    final ratings = allCaveDefs.where((d) => d.spec.id.startsWith('rating_'));
    expect(allCaveDefs.length - ratings.length, 45);
    final ids = allCaveDefs.map((d) => d.spec.id).toSet();
    expect(ids.length, allCaveDefs.length, reason: 'duplicate level ids');
  });

  group('playability', () {
    for (final def in allCaveDefs) {
      test(def.spec.id, () {
        final issues = validateCaveSpec(def.spec, ship: shipOfCave(def));
        expect(issues, isEmpty,
            reason: '${def.spec.id} failed:\n  ${issues.join('\n  ')}');
      });
    }
  });

  // Daily "Test Flight": the runtime chooser offers only swaps that pass the
  // full validator (LevelRegistry.testFlightOptions runs it), drawn from the
  // eligible hulls, and well-equipped worlds still get some variety.
  test('test flight options: validated swaps, usually at least one', () {
    var offered = 0;
    for (int i = 0; i < LevelRegistry.totalLevels; i++) {
      final options = LevelRegistry.testFlightOptions(i);
      final eligible = testFlightShips(LevelRegistry.shipFor(i)).map((s) => s.id);
      for (final ship in options) {
        expect(eligible, contains(ship.id), reason: LevelRegistry.defAt(i).saveId);
      }
      offered += options.length;
    }
    expect(offered, greaterThan(LevelRegistry.totalLevels),
        reason: 'Test Flight should usually have a ship to offer');
  });

  // The win sensors (DualLandingZone) reach kPadSensorDrop below the pad
  // box; the shelf floor is kPadFloorDrop below it. Whatever rests on the
  // floor — the pod, or any ship's hull standing upright — must reach up
  // into the sensors, on every level alike.
  test('a pod or any hull resting on a pad floor reaches the win sensors', () {
    const overlap = kPadSensorDrop - kPadFloorDrop;
    expect(2 * kCargoRadius, greaterThan(0.1 - overlap), reason: 'pod');
    for (final ship in kShips.values) {
      expect(ship.rearLocalY - ship.noseLocalY, greaterThan(0.1 - overlap),
          reason: ship.id);
    }
  });

  // The shelf itself: air just above the floor, rock just under it, across
  // the pad (rating_mule's pad used to hang over a slope).
  group('landing pads', () {
    for (final def in allCaveDefs) {
      test(def.spec.id, () {
        final g = def.spec.goal;
        final cave = buildCave(def.spec);
        final floorY = padFloorY(g);
        for (int k = 0; k <= 8; k++) {
          final x = g.center.x - g.halfW + 0.2 + k * (2 * g.halfW - 0.4) / 8;
          expect(cave.fieldAt(x, floorY - 0.05), lessThan(0),
              reason: '${def.spec.id}: no air just above the pad floor at x $x');
          expect(cave.fieldAt(x, floorY + 0.05), greaterThan(0),
              reason: '${def.spec.id}: no rock under the pad at x $x');
        }
        // Simplification ran: no raw marching-squares outline.
        for (final loop in cave.loops) {
          expect(loop.length, lessThan(4000),
              reason: '${def.spec.id} unsimplified loop (${loop.length} pts)');
        }
      });
    }
  });

  test('deterministic: a fresh build matches the cached one exactly', () {
    final spec = allCaveDefs.first.spec;
    final a = buildCave(spec);
    final b = buildCaveUncached(spec);
    expect(b.loops.length, a.loops.length);
    for (int i = 0; i < a.loops.length; i++) {
      expect(b.loops[i].length, a.loops[i].length);
      for (int j = 0; j < a.loops[i].length; j++) {
        expect(b.loops[i][j].x, a.loops[i][j].x);
        expect(b.loops[i][j].y, a.loops[i][j].y);
      }
    }
  });

  // Wall-clock budget: meaningless on a busy CI runner, so it runs on demand
  // (`flutter test --tags perf --run-skipped`).
  test('build time stays within budget', () {
    final sw = Stopwatch()..start();
    for (final def in allCaveDefs) {
      buildCaveUncached(def.spec);
    }
    sw.stop();
    final perLevelMs = sw.elapsedMilliseconds / allCaveDefs.length;
    expect(perLevelMs, lessThan(250),
        reason: 'avg cave build ${perLevelMs.toStringAsFixed(0)} ms/level');
  }, tags: 'perf');
}
