// What a delivery remembers beyond stars: the best fuel, flawless runs, the
// result screen's "new best" facts and the ghost of the pilot's own best
// flight, in the real game. Plus the pure pieces behind the mid-flight star
// cue and the hangar's next goal.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/route/personal_best_routes.dart';
import 'package:narrow_haul/game/run/star_watch.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/career_goal.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'autopilot/harness.dart';

void main() {
  group('StarWatch', () {
    test('each mark fires once, on the way down', () {
      final w = StarWatch()..reset([0.7, 0.4]);
      expect(w.update(0.9), isNull);
      expect(w.update(0.69), 0);
      expect(w.update(0.6), isNull);
      expect(w.update(0.75), isNull, reason: 'a canister back above');
      expect(w.update(0.65), isNull, reason: 'a lost mark stays lost');
      expect(w.update(0.39), 1);
      expect(w.update(0.1), isNull);
      expect(w.lostCount, 2);
    });

    test('a big drop past both marks reports the lower one', () {
      final w = StarWatch()..reset([0.7, 0.4]);
      expect(w.update(0.3), 1);
      expect(w.lostCount, 2);
    });

    test('marks already under the tank at the start stay quiet', () {
      final w = StarWatch()..reset([0.7, 0.4], fuel: 0.5);
      expect(w.update(0.45), isNull);
      expect(w.update(0.35), 1);
    });

    test('no marks, no cues', () {
      final w = StarWatch()..reset(const []);
      expect(w.update(0), isNull);
    });
  });

  group('careerGoal', () {
    const worlds = [
      (name: 'Training Grounds', starsRequired: 0),
      (name: 'Xenar Caverns', starsRequired: 8),
      (name: 'Rustshaft Mines', starsRequired: 22),
    ];

    test('the next locked world first', () {
      expect(careerGoal(stars: 5, missions: 20, flawless: 0, worlds: worlds), '3★ to Xenar Caverns');
      expect(careerGoal(stars: 9, missions: 20, flawless: 0, worlds: worlds), '13★ to Rustshaft Mines');
    });

    test('then stars left, then flawless runs', () {
      expect(careerGoal(stars: 50, missions: 20, flawless: 0, worlds: worlds), '10★ left to earn');
      expect(careerGoal(stars: 60, missions: 20, flawless: 18, worlds: worlds), '2 flawless runs to go');
      expect(careerGoal(stars: 60, missions: 20, flawless: 19, worlds: worlds), '1 flawless run to go');
      expect(careerGoal(stars: 60, missions: 20, flawless: 20, worlds: worlds), 'Every mission flawless');
    });
  });

  group('bests in the real game', () {
    final h = GameHarness();
    late Directory dir;
    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('pb_routes');
      PersonalBestRoutes.debugDir = dir;
      PersonalBestRoutes.debugClearCache();
      await h.boot();
    });
    tearDownAll(() async {
      PersonalBestRoutes.debugDir = null;
      await dir.delete(recursive: true);
    });

    /// The booking's unawaited writes, and the ghost's real file write.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    /// Launches and hovers for [seconds] (thrust only while sinking).
    Future<void> hover(double seconds) => h.fly(
          (f) => BotInput(thrust: f == 0 || h.game.ship!.body.linearVelocity.y > 0),
          maxSeconds: seconds,
        );

    // tut_04: no onboarding hints, a plain Kestrel mission.
    const level = 3;
    final saveId = LevelRegistry.defAt(level).saveId;

    test('a first clear saves best fuel, flawless and the ghost', () async {
      final p = ProgressService.instance;
      await h.loadLevel(level);
      await hover(2);
      expect(h.game.runState, RunState.playing);
      await h.game.debugDeliver();
      await settle();
      final r = h.game.lastRunReward!;
      expect(r.firstClear, isTrue);
      expect(r.personalBest, isFalse, reason: 'nothing to beat yet');
      expect(p.getBestFuelById(saveId), closeTo(h.game.lastLevelFuelFraction, 1e-9));
      if (h.game.lastLevelStars == 3) {
        expect(r.newFlawless, isTrue);
        expect(p.isFlawless(saveId), isTrue);
      }
      expect(p.pbRouteSeconds(saveId), closeTo(h.game.lastLevelTimeSeconds, 1e-6));
      expect(File('${dir.path}/pb_routes/$saveId.json').existsSync(), isTrue);
    });

    test('a faster replay is a new best and becomes the ghost', () async {
      final p = ProgressService.instance;
      final before = p.pbRouteSeconds(saveId)!;
      await h.loadLevel(level);
      expect(h.game.personalBestRoute, isNotNull, reason: 'the saved ghost loads');
      expect(h.game.raceGhostAvailable, isTrue);
      await hover(0.5);
      await h.game.debugDeliver();
      await settle();
      final r = h.game.lastRunReward!;
      expect(r.firstClear, isFalse);
      expect(r.personalBest, isTrue);
      expect(r.previousBestTime, closeTo(before, 1e-6));
      expect(r.newFlawless, isFalse, reason: 'flawless is paid once');
      expect(p.pbRouteSeconds(saveId), lessThan(before));
    });

    test('a wall scrape is never flawless', () async {
      final p = ProgressService.instance;
      const other = 4; // tut_05
      final id = LevelRegistry.defAt(other).saveId;
      await h.loadLevel(other);
      await hover(1);
      h.game.wallScrapesThisRun = 1;
      await h.game.debugDeliver();
      await settle();
      expect(h.game.lastRunReward!.newFlawless, isFalse);
      expect(p.isFlawless(id), isFalse);
    });

    test('a whole world flawless unlocks Greaser', () async {
      final p = ProgressService.instance;
      final (world, _) = LevelRegistry.worldOf(level);
      for (final d in world.levels) {
        if (d.saveId != LevelRegistry.defAt(4).saveId) await p.markFlawless(d.saveId);
      }
      expect(AchievementService.unlocked, isNot(contains(AchievementIds.flawlessWorld)));
      // tut_05, the one left: a clean 3★ delivery finishes the set.
      await h.loadLevel(4);
      await hover(0.5);
      await h.game.debugDeliver();
      await settle();
      expect(h.game.lastLevelStars, 3);
      expect(h.game.lastRunReward!.newFlawless, isTrue);
      expect(
        h.game.lastRunReward!.newAchievements.map((a) => a.id),
        contains(AchievementIds.flawlessWorld),
      );
    });

    test('a slower replay keeps the old ghost', () async {
      final p = ProgressService.instance;
      final best = p.pbRouteSeconds(saveId)!;
      await h.loadLevel(level);
      await hover(3);
      await h.game.debugDeliver();
      await settle();
      expect(h.game.lastRunReward!.personalBest, isFalse);
      expect(p.pbRouteSeconds(saveId), best);
    });
  });
}
