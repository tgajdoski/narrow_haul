// What a delivery pays (coins for new stars × rank multiplier, rank-up
// bonuses, 2× coins once) and the rewarded continue after a crash, in the
// real game.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';

import 'autopilot/harness.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  /// Lets the unawaited save writes of the booking land.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Coins a delivery should pay: new stars at the world rate × the rank
  /// multiplier before the flight, plus each rank crossed.
  int expectedCoins({required int newStars, required RunReward r}) {
    final world = LevelRegistry.worldOf(h.game.levelIndex).$1;
    var coins = (newStars * world.rewardPerStar * (1 + rankFor(r.xpBefore).currencyBonus)).round();
    for (var i = rankFor(r.xpBefore).index + 1; i <= rankFor(r.xpAfter).index; i++) {
      coins += rankUpBonus(kRanks[i]);
    }
    return coins;
  }

  group('delivery booking', () {
    test('a first clear pays for its stars and saves them', () async {
      final p = ProgressService.instance;
      final coins = p.getCosmeticCurrency();
      await h.loadLevel(0);
      await h.game.debugDeliver();
      await settle();
      final stars = h.game.lastLevelStars;
      final r = h.game.lastRunReward!;
      expect(stars, inInclusiveRange(1, 3));
      expect(p.getStarsById(LevelRegistry.defAt(0).saveId), stars);
      expect(r.currency, expectedCoins(newStars: stars, r: r));
      expect(p.getCosmeticCurrency(), coins + r.currency);
      expect(p.getXp(), r.xpAfter);
      expect(r.xpAfter, greaterThan(r.xpBefore));
    });

    test('2× coins pays the run once more, only once', () async {
      final p = ProgressService.instance;
      expect(h.game.canDoubleCurrency, isTrue);
      final paid = h.game.lastRunReward!.currency;
      final coins = p.getCosmeticCurrency();
      await h.game.doubleRunCurrency();
      expect(p.getCosmeticCurrency(), coins + paid);
      expect(h.game.lastRunReward!.currency, paid * 2);
      expect(h.game.canDoubleCurrency, isFalse);
      await h.game.doubleRunCurrency();
      expect(p.getCosmeticCurrency(), coins + paid);
    });

    test('a replay with no new stars pays no star coins', () async {
      final p = ProgressService.instance;
      final coins = p.getCosmeticCurrency();
      await h.loadLevel(0);
      await h.game.debugDeliver();
      await settle();
      final r = h.game.lastRunReward!;
      expect(r.currency, expectedCoins(newStars: 0, r: r));
      expect(p.getCosmeticCurrency(), coins + r.currency);
    });
  });

  group('continue after a crash', () {
    /// Launches and hovers in open air for [seconds] (thrust only while
    /// sinking) so the game banks safe points.
    Future<void> hover(double seconds) => h.fly(
          (f) => BotInput(thrust: f == 0 || h.game.ship!.body.linearVelocity.y > 0),
          maxSeconds: seconds,
        );

    test('rewinds once per attempt, tops up fuel and caps the run at 2★', () async {
      final g = h.game;
      await h.loadLevel(0);
      expect(g.canContinue, isFalse, reason: 'nothing to continue yet');
      await hover(3);
      expect(g.runState, RunState.playing, reason: 'the hover must not crash');
      final fuel = g.ship!.fuel;
      final clock = g.elapsedSeconds;
      g.onShipShot();
      expect(g.runState, RunState.gameOver);
      expect(g.canContinue, isTrue);

      g.continueAfterCrash();
      expect(g.runState, RunState.playing);
      expect(g.continuedThisRun, isTrue);
      expect(g.ship!.fuel, greaterThan(fuel), reason: 'fuel top-up');
      expect(g.ship!.fuel, lessThanOrEqualTo(g.ship!.maxFuel));
      expect(g.elapsedSeconds, clock, reason: 'the clock keeps the crash time');
      expect(g.debugStars(1, 1), 2);

      await hover(2);
      g.onShipShot();
      expect(g.canContinue, isFalse, reason: 'once per attempt');

      // A new attempt can continue again and is uncapped.
      await h.loadLevel(0);
      expect(g.continuedThisRun, isFalse);
      expect(g.debugStars(1, 1), 3);
    });

    test('no continue for a crash on the pad before launch', () async {
      await h.loadLevel(0);
      h.game.onShipShot();
      expect(h.game.canContinue, isFalse);
    });
  });
}
