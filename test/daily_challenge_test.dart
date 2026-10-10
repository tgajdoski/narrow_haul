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
    final spec = LevelRegistry.flat.whereType<CaveLevelDef>().first.spec;
    forgetCave(spec.id);
    expect(isCaveCached(spec.id), isFalse);
    await prebuildCave(spec);
    expect(isCaveCached(spec.id), isTrue);
    final cached = buildCave(spec);
    final fresh = buildCaveUncached(spec);
    expect([for (final l in cached.loops) l.length], [for (final l in fresh.loops) l.length]);
    expect(cached.loops.first.first.x, fresh.loops.first.first.x);
  });
}
