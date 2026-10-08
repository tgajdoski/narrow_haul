// ignore_for_file: invalid_use_of_internal_member
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/combat/intercept.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

import 'autopilot/harness.dart';

int _levelId(String id) {
  for (int i = 0; i < LevelRegistry.totalLevels; i++) {
    final def = LevelRegistry.defAt(i);
    if (def is CaveLevelDef && def.spec.id == id) return i;
  }
  throw StateError('no level $id');
}

void main() {
  group('rules', () {
    test('strength: the cannon and flak trade, heavier rounds pierce', () {
      expect(resolveIntercept(interceptStrength(null)), InterceptOutcome.trade);
      expect(resolveIntercept(interceptStrength(kCannon)), InterceptOutcome.trade);
      expect(resolveIntercept(interceptStrength(kFlak)), InterceptOutcome.trade);
      for (final w in [kSeeker, kGravityBomb, kDemoCharge, kMiningLaser]) {
        if (w == kMiningLaser) continue; // a beam, never a round
        expect(resolveIntercept(interceptStrength(w)), InterceptOutcome.pierce, reason: w.id);
      }
      expect(resolveIntercept(1, enemy: 2), InterceptOutcome.blocked);
    });

    test('swept check catches rounds that cross inside one step', () {
      // Head-on at 13.5 m/s: they swap sides within the step, never closer
      // than 0.2 m at either end.
      expect(sweptCircleHit(0, 0, 0.15, 0, 0.12, 0, 0.045, 0, kInterceptRadius), isTrue);
      expect(sweptCircleHit(0, 0, 0.3, 0, 0.3, 0, 0, 0, kInterceptRadius), isTrue);
      // Parallel lanes 0.4 m apart never meet.
      expect(sweptCircleHit(0, 0, 0.3, 0, 0.3, 0.4, 0, 0.4, kInterceptRadius), isFalse);
      // Far apart and moving apart.
      expect(sweptCircleHit(0, 0, -0.1, 0, 1, 0, 1.1, 0, kInterceptRadius), isFalse);
    });

    test('a shell crossing the laser beam burns', () {
      // Beam along x from 0 to 4; shell falls through it at x = 2.
      expect(sweptSegmentHit(2, -0.1, 2, 0.1, 0, 0, 4, 0, kLaserInterceptRadius), isTrue);
      expect(sweptSegmentHit(2, -0.5, 2, -0.3, 0, 0, 4, 0, kLaserInterceptRadius), isFalse);
      expect(sweptSegmentHit(5, -0.1, 5, 0.1, 0, 0, 4, 0, kLaserInterceptRadius), isFalse);
    });
  });

  group('in game', () {
    final h = GameHarness();
    setUpAll(h.boot);

    Shell shell(Vector2 at, Vector2 v, {required bool mine, WeaponSpec? weapon}) => Shell(
          position: at,
          velocity: v,
          fromPlayer: mine,
          host: h.game,
          world: h.game.world,
          color: const Color(0xFFFFFFFF),
          weapon: weapon,
        );

    Future<void> step(int frames) async {
      for (var i = 0; i < frames; i++) {
        h.game.update(kStepDt);
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a cannon round and a turret shell trade', () async {
      await h.loadLevel(_levelId('mine_01'));
      final game = h.game;
      final before = ProgressService.instance.getStat(ProgressService.statShellsIntercepted);
      final c = game.ship!.body.position + Vector2(0, -1.3);
      final enemy = shell(c + Vector2(-1, 0), Vector2(4.5, 0), mine: false);
      final round = shell(c + Vector2(1, 0), Vector2(-9, 0), mine: true);
      game.spawnShell(enemy);
      game.spawnShell(round);
      await step(20);
      expect(enemy.spent, isTrue);
      expect(round.spent, isTrue);
      expect(game.runState, isNot(RunState.gameOver));
      expect(ProgressService.instance.getStat(ProgressService.statShellsIntercepted), before + 1);
    });

    test('a seeker pierces a turret shell and flies on', () async {
      await h.loadLevel(_levelId('mine_01'));
      final game = h.game;
      final c = game.ship!.body.position + Vector2(0, -1.3);
      final enemy = shell(c + Vector2(-1, 0), Vector2(4.5, 0), mine: false);
      final missile = shell(c + Vector2(0.6, 0), Vector2(-5, 0), mine: true, weapon: kSeeker);
      game.spawnShell(enemy);
      game.spawnShell(missile);
      await step(12);
      expect(enemy.spent, isTrue);
      expect(missile.spent, isFalse);
    });

    test('a blast clears turret shells within its radius', () async {
      await h.loadLevel(_levelId('mine_01'));
      final game = h.game..debugSyncCarve = true;
      final c = game.ship!.body.position + Vector2(0, -1.3);
      final near = shell(c + Vector2(2, 0), Vector2.zero(), mine: false);
      final far = shell(c + Vector2(0, -0.1) + Vector2(kDemoCharge.blastRadius + 1, 0),
          Vector2.zero(), mine: false);
      game.spawnShell(near);
      game.spawnShell(far);
      await step(1);
      game.detonate(c, kDemoCharge);
      expect(near.spent, isTrue);
      expect(far.spent, isFalse);
    });
  });
}
