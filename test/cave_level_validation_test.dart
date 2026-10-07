import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/level/specs/world_alien.dart';
import 'package:narrow_haul/game/level/specs/world_ice.dart';
import 'package:narrow_haul/game/level/specs/world_lava.dart';
import 'package:narrow_haul/game/level/specs/world_mine.dart';
import 'package:narrow_haul/game/level/specs/world_orbit.dart';

void main() {
  final allCaveDefs = <CaveLevelDef>[
    ...alienLevels.whereType<CaveLevelDef>(),
    ...mineLevels.whereType<CaveLevelDef>(),
    ...iceLevels.whereType<CaveLevelDef>(),
    ...lavaLevels.whereType<CaveLevelDef>(),
    ...orbitLevels.whereType<CaveLevelDef>(),
  ];

  // Validate each level against the ship it is actually flown with.
  ShipSpec shipOf(CaveLevelDef def) {
    final world = LevelRegistry.worlds.firstWhere((w) => w.levels.contains(def));
    return shipById(def.shipId ?? world.defaultShipId);
  }

  test('cave worlds: 8 missions each (+ type ratings), unique ids', () {
    final ratings = allCaveDefs.where((d) => d.spec.id.startsWith('rating_'));
    expect(allCaveDefs.length - ratings.length, 40);
    final ids = allCaveDefs.map((d) => d.spec.id).toSet();
    expect(ids.length, allCaveDefs.length, reason: 'duplicate level ids');
  });

  group('playability', () {
    for (final def in allCaveDefs) {
      test(def.spec.id, () {
        final issues = validateCaveSpec(def.spec, ship: shipOf(def));
        expect(issues, isEmpty,
            reason: '${def.spec.id} failed:\n  ${issues.join('\n  ')}');
      });
    }
  });

  // Daily "Test Flight": the runtime chooser only offers swaps that pass the
  // full validator, and well-equipped worlds still get some variety.
  group('test flight options', () {
    test('every offered swap is provably completable', () {
      var offered = 0;
      for (int i = 0; i < LevelRegistry.totalLevels; i++) {
        final def = LevelRegistry.defAt(i);
        for (final ship in LevelRegistry.testFlightOptions(i)) {
          offered++;
          if (def is CaveLevelDef) {
            expect(validateCaveSpec(def.spec, ship: ship), isEmpty,
                reason: '${def.saveId} in ${ship.name}');
          }
        }
      }
      expect(offered, greaterThan(LevelRegistry.totalLevels),
          reason: 'Test Flight should usually have a ship to offer');
    });
  });

  group('builder invariants', () {
    test('deterministic — same spec builds identical loops', () {
      final spec = (alienLevels.first as CaveLevelDef).spec;
      clearCaveCache();
      final a = buildCave(spec);
      clearCaveCache();
      final b = buildCave(spec);
      expect(a.loops.length, b.loops.length);
      for (int i = 0; i < a.loops.length; i++) {
        expect(a.loops[i].length, b.loops[i].length);
        for (int j = 0; j < a.loops[i].length; j++) {
          expect(a.loops[i][j].x, b.loops[i][j].x);
          expect(a.loops[i][j].y, b.loops[i][j].y);
        }
      }
    });

    test('all loops are closed polygons with sane vertex counts', () {
      for (final def in allCaveDefs) {
        final cave = buildCave(def.spec);
        expect(cave.loops, isNotEmpty, reason: '${def.spec.id} has no terrain');
        for (final loop in cave.loops) {
          expect(loop.length, greaterThanOrEqualTo(4),
              reason: '${def.spec.id} degenerate loop');
          expect(loop.length, lessThan(4000),
              reason: '${def.spec.id} unsimplified loop (${loop.length} pts)');
        }
      }
    });

    test('build time stays within budget', () {
      clearCaveCache();
      final sw = Stopwatch()..start();
      for (final def in allCaveDefs) {
        buildCave(def.spec);
      }
      sw.stop();
      final perLevelMs = sw.elapsedMilliseconds / allCaveDefs.length;
      expect(perLevelMs, lessThan(250),
          reason: 'avg cave build ${perLevelMs.toStringAsFixed(0)} ms/level');
    });
  });
}
