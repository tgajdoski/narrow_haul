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
    /// tut_06: past the Training levels whose crashes rewind for free.
    const paid = 5;

    /// Launches and hovers in open air for [seconds] (thrust only while
    /// sinking) so the game banks safe points.
    Future<void> hover(double seconds) => h.fly(
          (f) => BotInput(thrust: f == 0 || h.game.ship!.body.linearVelocity.y > 0),
          maxSeconds: seconds,
        );

    test('rewinds once per attempt, tops up fuel and caps the run at 2★', () async {
      final g = h.game;
      await h.loadLevel(paid);
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
      await h.loadLevel(paid);
      expect(g.continuedThisRun, isFalse);
      expect(g.debugStars(1, 1), 3);
    });

    test('a continue hovers on 3 · 2 · 1 before flying on', () async {
      final g = h.game;
      await h.loadLevel(paid);
      await hover(3);
      g.onShipShot();
      g.continueAfterCrash();
      final s = g.ship!;
      expect(s.launched, isFalse, reason: 'held until the countdown ends');
      final pos = s.body.position.clone();
      final clock = g.elapsedSeconds;
      await h.step(120); // 2 s, no input
      expect(s.launched, isFalse);
      expect(s.body.position.distanceTo(pos), lessThan(0.01), reason: 'hovers');
      expect(g.elapsedSeconds, clock, reason: 'the clock waits');
      await h.step(70); // past GO
      expect(s.launched, isFalse, reason: 'GO never drops an untouched ship');
      expect(s.body.position.distanceTo(pos), lessThan(0.01), reason: 'still hovering');
      expect(g.elapsedSeconds, greaterThan(clock), reason: 'the clock runs from GO');
      expect(g.runState, RunState.playing);
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      expect(s.launched, isTrue, reason: 'the first input flies on');

      // Input during the hold flies on at once.
      await h.loadLevel(paid);
      await hover(3);
      g.onShipShot();
      g.continueAfterCrash();
      expect(g.ship!.launched, isFalse);
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      expect(g.ship!.launched, isTrue);
    });

    test('GO starts the clock but never drops an untouched ship', () async {
      final g = h.game;
      // Lava: the heaviest pull, where the old drop crashed hardest.
      await h.loadLevel(LevelRegistry.flat.indexWhere((d) => d.saveId == 'lava_08'));
      final s = g.ship!;
      final pos = s.body.position.clone();
      await h.step(60 * 8); // level card, 3 · 2 · 1 · GO and then some
      expect(g.runState, RunState.playing, reason: 'no crash');
      expect(s.launched, isFalse);
      expect(s.body.position.distanceTo(pos), lessThan(0.01), reason: 'still hovering');
      expect(g.elapsedSeconds, greaterThan(0), reason: 'the clock runs from GO');
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      expect(s.launched, isTrue);
    });

    test('no continue for a crash on the pad before launch', () async {
      await h.loadLevel(paid);
      h.game.onShipShot();
      expect(h.game.canContinue, isFalse);
    });

    test('early Training rewinds for free, upright, as often as needed', () async {
      final g = h.game;
      await h.loadLevel(0);
      await hover(3);
      g.onShipShot();
      expect(g.canContinue, isFalse, reason: 'no ad in Training');
      expect(g.canFreeContinue, isTrue);
      expect(g.crashAdvice, isNotNull);
      g.ship!.body.setTransform(g.ship!.body.position, 2.5);
      g.freeContinue();
      expect(g.runState, RunState.playing);
      expect(g.continuedThisRun, isFalse, reason: 'no star cap');
      expect(g.ship!.body.angle, closeTo(0, 1e-6), reason: 'starts upright');

      // Straight into another crash: it can still rewind.
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      g.onShipShot();
      expect(g.canFreeContinue, isTrue);
      g.freeContinue();
      expect(g.runState, RunState.playing);
      expect(g.debugStars(1, 1), 3);
    });
  });
}
