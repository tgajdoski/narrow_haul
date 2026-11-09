import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

void main() {
  test('daily only picks from the offered (unlocked) levels', () {
    const unlocked = [0, 1, 2, 3];
    final config = DailyChallengeConfig.forToday(unlocked);
    expect(unlocked, contains(config.levelIndex));
  });

  test('daily falls back to the first level when none are offered', () {
    expect(DailyChallengeConfig.forToday(const []).levelIndex, 0);
  });

  group('Salvage Chaos weekend', () {
    tearDown(() => ProgressService.clock = DateTime.now);

    test('is the first Saturday of the month and the Sunday after it', () {
      bool on(int y, int m, int d) =>
          DailyChallengeConfig.isChaosWeekend(DateTime.utc(y, m, d));
      expect(on(2026, 12, 5), isTrue); // Sat
      expect(on(2026, 12, 6), isTrue); // Sun
      expect(on(2026, 12, 12), isFalse); // second Sat
      expect(on(2026, 11, 7), isTrue); // Sat 7th
      expect(on(2026, 11, 8), isTrue); // Sun 8th
      expect(on(2026, 11, 1), isFalse); // Sun 1st: its Saturday was October
      expect(on(2026, 12, 4), isFalse); // Fri
    });

    test('forces chaos on a cave level, keeps the level draw', () {
      ProgressService.clock = () => DateTime.utc(2026, 12, 5, 12);
      const pool = [0, 1, 2, 3, 4, 5];
      final c = DailyChallengeConfig.forToday(pool, chaosOk: (_) => true);
      expect(c.chaos, isTrue);
      expect(c.modifierName, DailyChallengeConfig.chaosName);
      final (level, testFlight) = DailyChallengeConfig.peekToday(pool);
      expect(c.levelIndex, level);
      expect(testFlight, isFalse);
      // Training-only pilots (no cave level) get a standard run.
      final t = DailyChallengeConfig.forToday(pool, chaosOk: (_) => false);
      expect(t.chaos, isFalse);
    });
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
