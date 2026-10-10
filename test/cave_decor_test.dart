import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cave_decor.dart';
import 'package:narrow_haul/game/components/cave_terrain.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_registry.dart';

import 'helpers/caves.dart';

Future<CaveDecor> _decorFor(LevelData data) async {
  final edges = [
    for (final loop in data.caveLoops)
      ui.Path()..addPolygon([for (final p in loop) ui.Offset(p.x, p.y)], true),
  ];
  final decor = CaveDecor(
    loops: data.caveLoops,
    rockPath: CaveTerrain.buildRockPath(edges, data.worldSize),
    theme: data.theme,
    anchors: [
      for (final v in [data.shipSpawn, data.cargoSpawn, data.goalCenter])
        ui.Offset(v.x, v.y),
    ],
  );
  await decor.onLoad();
  return decor;
}

void main() {
  setUpAll(prebuildAllCaves);

  test('decor is deterministic, clear of anchors, and present in every world', () async {
    final perWorld = <String, int>{};
    for (final def in allCaveDefs) {
      final data = buildCaveLevelData(def);
      final a = (await _decorFor(data)).propTips;
      final b = (await _decorFor(data)).propTips;
      expect(a, b, reason: '${def.spec.id}: decor not deterministic');
      for (final tip in a) {
        for (final v in [data.shipSpawn, data.cargoSpawn, data.goalCenter]) {
          expect((tip - ui.Offset(v.x, v.y)).distance, greaterThan(2.0),
              reason: '${def.spec.id}: prop near anchor');
        }
      }
      perWorld.update(data.theme.id, (n) => n + a.length, ifAbsent: () => a.length);
    }
    for (final entry in perWorld.entries) {
      expect(entry.value, greaterThan(16), reason: '${entry.key} has too little decor');
    }
  });
}
