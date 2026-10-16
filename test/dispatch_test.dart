// The shared Daily dispatch: one day for everyone (08:00 UTC rollover), one
// level per career stage, the same draw on every phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/dispatch.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'helpers/pump.dart';

void main() {
  tearDown(() => ProgressService.clock = DateTime.now);

  group('dispatch day', () {
    test('rolls over at 08:00 UTC, whatever the phone\'s time zone', () {
      expect(dispatchKey(DateTime.utc(2026, 10, 16, 7, 59)), '2026-10-15');
      expect(dispatchKey(DateTime.utc(2026, 10, 16, 8)), '2026-10-16');
      // The same instant seen from Tokyo and Los Angeles.
      final t = DateTime.utc(2026, 10, 16, 12);
      expect(dispatchKey(t.add(const Duration(hours: 9)).toLocal()), dispatchKey(t.add(const Duration(hours: 9))));
      expect(nextDispatchAt(t), DateTime.utc(2026, 10, 17, 8));
    });

    test('every phone draws the same level and modifier for the same list', () {
      const pool = [3, 4, 5, 6, 7, 8, 9];
      ProgressService.clock = () => DateTime.utc(2026, 10, 16, 23);
      final a = DailyChallengeConfig.forToday(pool);
      // Another phone, other side of the world, same dispatch.
      ProgressService.clock = () => DateTime.utc(2026, 10, 17, 7);
      final b = DailyChallengeConfig.forToday(pool);
      expect(b.levelIndex, a.levelIndex);
      expect(b.modifierName, a.modifierName);
    });
  });

  group('dispatch stages', () {
    test('stage follows the worlds open', () {
      expect(DispatchTier.forUnlocked({'tutorial'}), DispatchTier.cadet);
      expect(DispatchTier.forUnlocked({'tutorial', 'alien', 'mine'}), DispatchTier.line);
      expect(DispatchTier.forUnlocked({'tutorial', 'alien', 'mine', 'ice', 'lava'}), DispatchTier.senior);
      expect(
        DispatchTier.forUnlocked({'tutorial', 'alien', 'mine', 'ice', 'lava', 'orbit', 'redoubt'}),
        DispatchTier.veteran,
      );
    });

    test('a stage draws from real worlds; never ratings, first flights, Expeditions or the Redoubt', () {
      final ids = {for (final w in LevelRegistry.worlds) w.id};
      for (final t in DispatchTier.values) {
        expect(ids.containsAll(t.worldIds), isTrue, reason: t.name);
        expect(t.worldIds, isNot(contains('redoubt')));
        expect(t.worldIds, isNot(contains('expeditions')));
      }
      expect(dispatchEligible('rating_hopper'), isFalse);
      expect(dispatchEligible('tut_01'), isFalse);
      expect(dispatchEligible('tut_03'), isTrue);
    });

    test('a new pilot and a pilot one star short of Xenar share the cadet list', () async {
      await freshSave();
      final fresh = NarrowHaulGame.dailyLevelIndices();
      expect(NarrowHaulGame.dispatchTier(), DispatchTier.cadet);
      expect(fresh, isNotEmpty);
      for (final i in fresh) {
        expect(LevelRegistry.worldOf(i).$1.id, 'tutorial');
      }
      await freshSave({
        for (final d in LevelRegistry.worlds.first.levels.take(7)) 'stars2_${d.saveId}': 1,
      });
      expect(NarrowHaulGame.dailyLevelIndices(), fresh, reason: 'same stage, same list');
    });

    test('the stage holds for the day when a world opens mid-day', () async {
      ProgressService.clock = () => DateTime.utc(2026, 10, 16, 12);
      await freshSave();
      expect(NarrowHaulGame.dispatchTier(), DispatchTier.cadet);
      // Enough stars to open the Xenar Caverns, earned that afternoon.
      for (final d in LevelRegistry.worlds.first.levels) {
        await ProgressService.instance.saveStarsById(d.saveId, 3);
      }
      expect(NarrowHaulGame.dispatchTier(), DispatchTier.cadet, reason: 'kept for the day');
      ProgressService.clock = () => DateTime.utc(2026, 10, 17, 9);
      expect(NarrowHaulGame.dispatchTier(), DispatchTier.line, reason: 'next dispatch');
    });
  });
}
