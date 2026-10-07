import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';

void main() {
  test('daily only picks from the offered (unlocked) levels', () {
    const unlocked = [0, 1, 2, 3];
    final config = DailyChallengeConfig.forToday(unlocked);
    expect(unlocked, contains(config.levelIndex));
  });

  test('daily falls back to the first level when none are offered', () {
    expect(DailyChallengeConfig.forToday(const []).levelIndex, 0);
  });

  test('peekToday matches forToday', () {
    const unlocked = [0, 1, 2, 3, 4, 5];
    final (level, _) = DailyChallengeConfig.peekToday(unlocked);
    expect(DailyChallengeConfig.forToday(unlocked).levelIndex, level);
  });

  test('Test Flight options compute the same on a background isolate', () async {
    final i = LevelRegistry.flat.indexWhere((d) => d.saveId == 'mine_02');
    final direct = [for (final s in LevelRegistry.testFlightOptions(i)) s.id];
    final viaIsolate = await Isolate.run(
      () => [for (final s in LevelRegistry.testFlightOptions(i)) s.id],
    );
    expect(viaIsolate, direct);
  });

  test('prebuildCave builds off-thread and fills the cache', () async {
    final def = LevelRegistry.flat.whereType<CaveLevelDef>().first;
    clearCaveCache();
    await prebuildCave(def.spec);
    final cached = buildCave(def.spec);
    clearCaveCache();
    final fresh = buildCave(def.spec);
    expect(cached.loops.length, fresh.loops.length);
    expect(cached.loops.first.length, fresh.loops.first.length);
  });
}
