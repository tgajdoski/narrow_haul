import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('rank ladder', () {
    test('ranks are ordered by XP', () {
      for (int i = 1; i < kRanks.length; i++) {
        expect(kRanks[i].minXp, greaterThan(kRanks[i - 1].minXp));
        expect(kRanks[i].index, i);
      }
    });

    test('rankFor boundaries', () {
      expect(rankFor(0).title, 'Student Pilot');
      expect(rankFor(399).title, 'Student Pilot');
      expect(rankFor(400).title, 'Private Pilot');
      expect(rankFor(8500).title, 'Captain');
      expect(rankFor(20000).title, 'Chief Pilot');
      expect(rankTitle(23000), 'Chief Pilot ★1');
      expect(prestigeStars(19999), 0);
    });

    test('progress to next rank', () {
      expect(progressToNext(0), 0);
      expect(progressToNext(200), closeTo(0.5, 1e-9));
      expect(stepProgress(21500), (1500, kPrestigeStepXp));
    });
  });

  group('computeRunXp', () {
    test('first clear with stars, clean flight', () {
      final xp = computeRunXp(
        challenge: false,
        firstClear: true,
        newStars: 3,
        tier: 2.0,
        cleanFlight: true,
        personalBest: true, // ignored on first clear
      );
      // 60×2 + 30×2×3 + 15
      expect(xp.total, 120 + 180 + 15);
    });

    test('replay is small and capped per day', () {
      final fresh = computeRunXp(
        challenge: false,
        firstClear: false,
        newStars: 0,
        tier: 1.0,
        cleanFlight: true,
        personalBest: true,
      );
      expect(fresh.total, 10 + 20 + 15);

      final nearCap = computeRunXp(
        challenge: false,
        firstClear: false,
        newStars: 0,
        tier: 1.0,
        cleanFlight: true,
        personalBest: true,
        replayXpUsedToday: kReplayXpDailyCap - 12,
      );
      expect(nearCap.total, 12);

      final capped = computeRunXp(
        challenge: false,
        firstClear: false,
        newStars: 0,
        tier: 1.0,
        cleanFlight: true,
        personalBest: false,
        replayXpUsedToday: kReplayXpDailyCap,
      );
      expect(capped.total, 0);
    });

    test('improving stars on a replay is not capped', () {
      final xp = computeRunXp(
        challenge: false,
        firstClear: false,
        newStars: 1,
        tier: 3.0,
        cleanFlight: false,
        personalBest: false,
        replayXpUsedToday: kReplayXpDailyCap,
      );
      expect(xp.total, 90);
    });

    test('daily challenge with streak bonus capped at 7 days', () {
      int daily(int streak) => computeRunXp(
            challenge: true,
            firstClear: false,
            newStars: 0,
            tier: 1,
            cleanFlight: false,
            personalBest: false,
            dailyFirstToday: true,
            dailyStreak: streak,
          ).total;
      expect(daily(1), 150);
      expect(daily(3), 150 + 75);
      expect(daily(30), 150 + 175);
    });
  });

  group('save_v3 migration', () {
    test('backfills XP from existing stars and achievements', () async {
      final tut = LevelRegistry.worlds[0].levels[0].saveId;
      final alien = LevelRegistry.worlds[1].levels[0].saveId;
      SharedPreferences.setMockInitialValues({
        'save_v2': true,
        'stars2_$tut': 3,
        'stars2_$alien': 1,
        'achievements': ['first_haul', 'unknown_id'],
      });
      await ProgressService.init();
      await CareerService.migrateIfNeeded();

      // tutorial: 60 + 90; alien (tier 1.5): 90 + 45; one known achievement.
      expect(ProgressService.instance.getXp(), 150 + 135 + 100);
      expect(ProgressService.instance.isXpMigrated, isTrue);

      // Runs only once.
      await ProgressService.instance.setXp(5);
      await CareerService.migrateIfNeeded();
      expect(ProgressService.instance.getXp(), 5);
    });

    test('fresh install starts at Student Pilot', () async {
      SharedPreferences.setMockInitialValues({});
      await ProgressService.init();
      await CareerService.migrateIfNeeded();
      expect(CareerService.rank.title, 'Student Pilot');
    });
  });
}
