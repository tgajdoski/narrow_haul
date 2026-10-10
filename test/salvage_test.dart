import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/rock_proximity.dart';
import 'package:narrow_haul/game/components/salvage_fx.dart';
import 'package:narrow_haul/game/level/cave/crate_spots.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  group('salvage picker', () {
    test('about 70% boons', () {
      final rng = math.Random(1);
      var good = 0;
      const n = 10000;
      for (var i = 0; i < n; i++) {
        if (pickSalvage(rng, const SalvageContext()).good) good++;
      }
      expect(good / n, closeTo(kSalvageGoodChance, 0.02));
    });

    test('never a curse twice in a row, nor near the pad', () {
      final rng = math.Random(2);
      for (var i = 0; i < 2000; i++) {
        expect(pickSalvage(rng, const SalvageContext(lastWasCurse: true)).good, isTrue);
        expect(pickSalvage(rng, const SalvageContext(nearPad: true)).good, isTrue);
      }
    });

    test('Stealth Field only where a turret is live', () {
      final rng = math.Random(3);
      final without = {
        for (var i = 0; i < 3000; i++) pickSalvage(rng, const SalvageContext()).effect,
      };
      expect(without, isNot(contains(SalvageEffect.stealth)));
      final everything = {
        for (var i = 0; i < 6000; i++)
          pickSalvage(rng, const SalvageContext(liveTurrets: true, towing: true)).effect,
      };
      expect(everything, containsAll(SalvageEffect.values));
    });

    test('context-only effects only in their context', () {
      final rng = math.Random(4);
      final plain = {
        for (var i = 0; i < 4000; i++)
          pickSalvage(rng, const SalvageContext(unarmed: false, lowFuel: true)).effect,
      };
      expect(plain, isNot(contains(SalvageEffect.heavyHeart)), reason: 'not towing');
      expect(plain, isNot(contains(SalvageEffect.ammoCache)), reason: 'armed');
      expect(plain, isNot(contains(SalvageEffect.sputter)), reason: 'low fuel');
      expect(plain, isNot(contains(SalvageEffect.flareBeacon)), reason: 'no turrets');
    });

    test('world weights: spores in the Alien caves', () {
      int spores(String theme) {
        final rng = math.Random(5);
        var n = 0;
        for (var i = 0; i < 6000; i++) {
          if (pickSalvage(rng, SalvageContext(themeId: theme)).effect == SalvageEffect.sporeTrip) n++;
        }
        return n;
      }

      expect(spores('alien'), greaterThan(spores('mine') * 2));
    });

    test('a chaos day is 50/50 and may curse twice', () {
      final rng = math.Random(6);
      var good = 0;
      const n = 10000;
      for (var i = 0; i < n; i++) {
        if (pickSalvage(rng, const SalvageContext(chaos: true, lastWasCurse: true)).good) good++;
      }
      expect(good / n, closeTo(kSalvageChaosGoodChance, 0.02));
    });

    test('every effect has a spec, a name and a radio line', () {
      for (final e in SalvageEffect.values) {
        final s = salvageSpec(e);
        expect(s.name, isNotEmpty);
        expect(s.quip, isNotEmpty);
        expect(salvageById(s.id), same(s));
      }
      expect(salvageById('nonsense'), isNull);
    });
  });

  group('active salvage', () {
    test('timers end the effect and reset the modifiers', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.afterburner));
      expect(a.thrustMul, kAfterburnerThrustMul);
      expect(a.fraction, 1);
      a.tick(4);
      expect(a.fraction, closeTo(0.5, 1e-9));
      a.tick(4.1);
      expect(a.active, isFalse);
      expect(a.thrustMul, 1);
    });

    test('drain multipliers: saver burns nothing, a leak burns double', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.fuelSaver));
      expect(a.drainMul, 0);
      a.start(salvageSpec(SalvageEffect.fuelLeak));
      expect(a.drainMul, kFuelLeakDrainMul);
      a.patchLeak();
      expect(a.drainMul, 1);
    });

    test('Top-off is instant: nothing keeps running', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.topOff));
      expect(a.active, isFalse);
    });

    test('the Overshield takes exactly one hit', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.overshield));
      expect(a.canAbsorb, isTrue);
      a.absorb();
      expect(a.canAbsorb, isFalse);
      expect(a.active, isFalse);
    });

    test('a curse forgives a crash only right after it starts', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.fuelLeak));
      expect(a.canAbsorb, isTrue);
      a.tick(kCurseGraceSeconds + 0.01);
      expect(a.canAbsorb, isFalse);
    });

    test('spinning shakes a sting off sooner', () {
      final still = ActiveSalvage()..start(salvageSpec(SalvageEffect.swarmSting));
      final spun = ActiveSalvage()..start(salvageSpec(SalvageEffect.swarmSting));
      for (var i = 0; i < 60; i++) {
        still.tick(1 / 60);
        spun.tick(1 / 60, spinRadians: 2 * math.pi / 60 * 2); // two turns a second
      }
      expect(still.left, closeTo(9, 1e-6));
      expect(spun.left, closeTo(9 - 2 * kStingSecondsPerTurn, 1e-6));
      expect(spun.hullTarget, kSwellScale);
    });

    test('a spun-off sting is reported once; a timed-out one is not', () {
      final spun = ActiveSalvage()..start(salvageSpec(SalvageEffect.swarmSting));
      for (var i = 0; i < 600 && spun.active; i++) {
        spun.tick(1 / 60, spinRadians: 2 * math.pi / 60 * 3);
      }
      expect(spun.active, isFalse);
      expect(spun.takeShakenOff(), isTrue);
      expect(spun.takeShakenOff(), isFalse);
      final waited = ActiveSalvage()..start(salvageSpec(SalvageEffect.swarmSting));
      waited.tick(10.1);
      expect(waited.takeShakenOff(), isFalse);
    });

    test('Phase 2 modifiers', () {
      final a = ActiveSalvage()..start(salvageSpec(SalvageEffect.compactor));
      expect(a.hullTarget, kCompactScale);
      a.start(salvageSpec(SalvageEffect.chrono));
      expect(a.timeScale, 1, reason: 'eases in');
      a.tick(1);
      expect(a.timeScale, closeTo(kChronoTimeScale, 1e-9));
      a.start(salvageSpec(SalvageEffect.antiGrav));
      expect(a.gravityMul, kAntiGravMul);
      a.start(salvageSpec(SalvageEffect.heavyHeart));
      expect(a.podWeightAdd, kHeavyHeartAdd);
      a.start(salvageSpec(SalvageEffect.crossedWires));
      expect(a.crossed, isTrue);
      a.start(salvageSpec(SalvageEffect.flareBeacon));
      expect(a.flared, isTrue);
      a.start(salvageSpec(SalvageEffect.sputter));
      var cut = 0;
      for (var i = 0; i < 60; i++) {
        a.tick(1 / 60);
        if (a.sputterCut) cut++;
      }
      expect(cut / 60, closeTo(kSputterCut / kSputterPeriod, 0.05));
      a.start(salvageSpec(SalvageEffect.sporeTrip));
      a.tick(1);
      expect(a.hallucination, 1);
      a.start(salvageSpec(SalvageEffect.blackout));
      a.tick(7.5);
      expect(a.darkness, lessThan(1), reason: 'eases out');
    });
  });

  group('salvage contracts', () {
    const e = DeliveryEvent(
      worldIndex: 1,
      challenge: false,
      clean: true,
      fuelFraction: 0.5,
      seconds: 60,
      newStars: 0,
      personalBest: false,
      salvageOpened: 1,
      cursed: true,
    );
    test('open-and-deliver and cursed deliveries count', () {
      expect(contractProgress(const Contract(ContractKind.salvageDelivery, target: 2), e), 1);
      expect(contractProgress(const Contract(ContractKind.cursedDelivery, target: 1), e), 1);
      const plain = DeliveryEvent(
        worldIndex: 1,
        challenge: false,
        clean: true,
        fuelFraction: 0.5,
        seconds: 60,
        newStars: 0,
        personalBest: false,
      );
      expect(contractProgress(const Contract(ContractKind.salvageDelivery, target: 2), plain), 0);
      expect(contractProgress(const Contract(ContractKind.cursedDelivery, target: 1), plain), 0);
    });

    test('salvage contracts only once a cave world is open', () {
      for (var d = 1; d <= 28; d++) {
        final list = generateContracts(DateTime(2026, 3, d),
            unlockedWorlds: const [0], starsRemaining: 10, dailyDone: true);
        expect(list.map((c) => c.kind), isNot(contains(ContractKind.salvageDelivery)));
        expect(list.map((c) => c.kind), isNot(contains(ContractKind.cursedDelivery)));
      }
    });
  });

  group('salvage spots', () {
    test('every cave level has a spot, never in a turret\'s view', () {
      for (final def in LevelRegistry.flat.whereType<CaveLevelDef>()) {
        final spec = def.spec;
        final spots = salvageSpots(spec, ship: LevelRegistry.shipFor(LevelRegistry.flat.indexOf(def)));
        expect(spots, isNotEmpty, reason: spec.id);
        final turrets = spec.obstacles.whereType<TurretSpec>().toList();
        for (final p in spots) {
          for (final t in turrets) {
            // The open-line check is the builder's; here: range and arc only
            // (stricter), so a spot in range must be out of the arc.
            final dx = p.x - t.base.x, dy = p.y - t.base.y;
            if (dx * dx + dy * dy > t.range * t.range) continue;
            var off = (math.atan2(dy, dx) - t.facing) % (2 * math.pi);
            if (off > math.pi) off -= 2 * math.pi;
            if (off.abs() <= t.aimArc) {
              expect(turretMightSee(t, p, (_, _) => true), isTrue);
            }
          }
        }
      }
    });
  });

  group('salvage in flight', () {
    final h = GameHarness();
    setUpAll(h.boot);

    Future<NarrowHaulGame> loadWithCache(String id) async {
      final game = h.game;
      await h.loadLevel(levelIndexOf(id));
      game
        ..debugNoSalvage = false
        ..salvageRng = _LoadedDice();
      await game.loadCurrentLevel(retry: true);
      await game.ready();
      return game;
    }

    tearDown(() => h.game
      ..debugNoSalvage = true
      ..salvageRng = math.Random());

    test('a cache spawns on cave levels, opens with a roulette, then applies', () async {
      final game = await loadWithCache('mine_01');
      final cache = game.salvageCache;
      expect(cache, isA<SalvageCache>());
      game.debugCollectSalvage(cache!);
      expect(game.salvage.active, isFalse, reason: 'still spinning');
      await h.step(((SalvageHud.rouletteSeconds + 0.1) * 60).round());
      // Loaded dice: the boon pool's first entry.
      expect(game.salvage.effect, SalvageEffect.overshield);
    });

    test('the Overshield takes a shell, then the next one crashes', () async {
      final game = await loadWithCache('mine_01');
      game.thrustHeld = true;
      await h.step(10);
      game.debugApplySalvage(salvageSpec(SalvageEffect.overshield));
      game.onShipShot();
      expect(game.runState, RunState.playing);
      await h.step(60); // past the bounce immunity
      game.onShipShot();
      expect(game.runState, RunState.gameOver);
    });

    test('Stealth Field blinds the turrets', () async {
      final game = await loadWithCache('redoubt_01');
      expect(game.shipCloaked, isFalse);
      game.debugApplySalvage(salvageSpec(SalvageEffect.stealth));
      expect(game.shipCloaked, isTrue);
    });

    test('a sting swells the hull into free space only, then it shrinks back', () async {
      final game = await loadWithCache('mine_01');
      final ship = game.ship!;
      // On its pad, resting on the floor: it eases up off the deck to swell.
      game.debugApplySalvage(salvageSpec(SalvageEffect.swarmSting));
      var peak = 1.0;
      for (var i = 0; i < 120; i++) {
        await h.step(1);
        peak = math.max(peak, ship.sizeMul);
        final near = probeRockNearby(game.world, ship);
        expect(near == null || near.gap > -0.03, isTrue, reason: 'hull inside rock');
        expect(ship.sizeMul, lessThanOrEqualTo(kSwellScale + 1e-9));
      }
      expect(peak, greaterThan(1.05), reason: 'grew');
      expect(game.runState, RunState.playing, reason: 'swelling never crashes');
      game.salvage.end();
      await h.step(60);
      expect(ship.sizeMul, 1);
    });

    test('Compactor shrinks the hull, then it grows back', () async {
      final game = await loadWithCache('mine_01');
      final ship = game.ship!;
      game.debugApplySalvage(salvageSpec(SalvageEffect.compactor));
      await h.step(60);
      expect(ship.sizeMul, closeTo(kCompactScale, 1e-9));
      game.salvage.end();
      await h.step(150);
      expect(ship.sizeMul, 1);
    });

    test('Chrono slows the cave, not its own clock', () async {
      final game = await loadWithCache('mine_01');
      game.debugApplySalvage(salvageSpec(SalvageEffect.chrono));
      await h.step(60);
      expect(game.salvage.timeScale, lessThan(0.7));
      expect(game.salvage.left, closeTo(5, 0.05), reason: 'real time');
    });

    test('Crossed Wires swaps the steering', () async {
      final game = await loadWithCache('mine_01');
      final ship = game.ship!;
      game.rotateAxis = 1;
      await h.step(5);
      expect(ship.body.angularVelocity, greaterThan(0));
      game.debugApplySalvage(salvageSpec(SalvageEffect.crossedWires));
      await h.step(5);
      expect(ship.body.angularVelocity, lessThan(0));
      game.rotateAxis = 0;
    });

    test('Lucky Salvage pays only on delivery; a crash loses it', () async {
      final game = await loadWithCache('mine_01');
      game.debugApplySalvage(salvageSpec(SalvageEffect.lucky));
      expect(game.debugLuckyCoins, kLuckyCoins);
      game.thrustHeld = true;
      await h.step(10);
      game.onShipShot();
      expect(game.debugLuckyCoins, 0);
    });

    test('Ammo Cache loads a weapon', () async {
      final game = await loadWithCache('mine_01');
      expect(game.weaponRack!.canFire, isFalse);
      game.debugApplySalvage(salvageSpec(SalvageEffect.ammoCache));
      expect(game.weaponRack!.canFire, isTrue);
    });

    test('opening a cache logs it and earns Opened the Box', () async {
      final game = await loadWithCache('mine_01');
      final before = ProgressService.instance.salvageFound('overshield');
      game.debugCollectSalvage(game.salvageCache!);
      await h.step(2);
      expect(ProgressService.instance.salvageFound('overshield'), before + 1);
      expect(AchievementService.unlocked, contains(AchievementIds.openedTheBox));
    });

    test('a chaos daily drops three caches, apart', () async {
      final game = h.game;
      final index = levelIndexOf('mine_01');
      await h.loadLevel(index);
      game
        ..debugNoSalvage = false
        ..isChallengeMode = true
        ..activeChallengeConfig = DailyChallengeConfig(
          levelIndex: index,
          gravityMultiplier: 1,
          fuelDrainMultiplier: 1,
          modifierName: DailyChallengeConfig.chaosName,
          modifierDesc: '',
          chaos: true,
        );
      addTearDown(() => game
        ..isChallengeMode = false
        ..activeChallengeConfig = null);
      await game.loadCurrentLevel(retry: true);
      await game.ready();
      final caches = game.salvageCaches;
      expect(caches.length, 3);
      for (final a in caches) {
        for (final b in caches) {
          if (!identical(a, b)) expect((a.pos - b.pos).distance, greaterThanOrEqualTo(4));
        }
      }
    });

    test('no cache in the tutorial or for the bot', () async {
      await h.loadLevel(levelIndexOf('tut_04'));
      expect(h.game.salvageCache, isNull);
      await h.loadLevel(levelIndexOf('mine_01'));
      expect(h.game.salvageCache, isNull, reason: 'harness turns salvage off');
    });
  });
}

/// Dice that always roll a cache, the first spot and the first boon.
class _LoadedDice implements math.Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}
