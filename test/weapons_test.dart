// ignore_for_file: invalid_use_of_internal_member
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cave_terrain.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  group('weapon specs', () {
    test('ids unique, names set, crate ranges sane', () {
      final ids = kWeapons.map((w) => w.id).toSet();
      expect(ids.length, kWeapons.length);
      expect(ids.contains(kCannon.id), isFalse);
      for (final w in kWeapons) {
        expect(w.name, isNotEmpty);
        expect(w.heavy, isTrue, reason: w.id);
        expect(w.crateMin, greaterThan(0), reason: w.id);
        expect(w.crateMax, greaterThanOrEqualTo(w.crateMin), reason: w.id);
        expect(w.coinCost, greaterThan(0), reason: w.id);
        expect(weaponById(w.id), same(w));
      }
      expect(kCannon.heavy, isFalse, reason: 'the cannon must not break machinery');
    });

    test('rock-carving weapons are the charge, the bomb and the laser', () {
      expect(
        kWeapons.where((w) => w.carvesRock).map((w) => w.id).toSet(),
        {kDemoCharge.id, kGravityBomb.id, kMiningLaser.id},
      );
    });
  });

  group('weapon rack', () {
    test('found ammo is spent before carried, and only carried costs 3★', () {
      final rack = WeaponRack(carried: {kGravityBomb.id: 2});
      rack.addFound(kGravityBomb.id, 1);
      expect(rack.ammo(kGravityBomb.id), 3);
      expect(rack.spend(kGravityBomb.id, 1), isTrue);
      expect(rack.usedCarried, isFalse);
      expect(rack.spend(kGravityBomb.id, 1), isTrue);
      expect(rack.usedCarried, isTrue);
      expect(rack.takeCarriedSpent(), {kGravityBomb.id: 1});
      expect(rack.takeCarriedSpent(), isEmpty);
    });

    test('empty weapons drop out and the selection moves on', () {
      final rack = WeaponRack(hasCannon: true, carried: {kFlak.id: 1});
      expect(rack.available, [kCannon.id, kFlak.id]);
      expect(rack.selectedId, kCannon.id);
      rack.cycle();
      expect(rack.selectedId, kFlak.id);
      expect(rack.spend(kFlak.id, 1), isTrue);
      expect(rack.available, [kCannon.id]);
      expect(rack.selectedId, kCannon.id);
      expect(rack.spend(kFlak.id, 1), isFalse);
    });

    test('the laser drains seconds and takes what is left', () {
      final rack = WeaponRack()..addFound(kMiningLaser.id, 0.05);
      expect(rack.canFire, isTrue);
      expect(rack.spend(kMiningLaser.id, 1 / 60), isTrue);
      expect(rack.spend(kMiningLaser.id, 0.1), isTrue);
      expect(rack.canFire, isFalse);
    });

    test('select picks a weapon on board, ignores the rest', () {
      final rack = WeaponRack(hasCannon: true, carried: {kGravityBomb.id: 2});
      expect(rack.selectedId, kCannon.id);
      expect(rack.select(kGravityBomb.id), isTrue);
      expect(rack.selectedId, kGravityBomb.id);
      expect(rack.select(kFlak.id), isFalse, reason: 'no flak on board');
      expect(rack.select('nonsense'), isFalse);
      expect(rack.selectedId, kGravityBomb.id);
    });

    test('the −★ badge shows only while the next shot spends carried ammo', () {
      final rack = WeaponRack(carried: {kGravityBomb.id: 2});
      rack.addFound(kGravityBomb.id, 1);
      expect(rack.costsStar(kGravityBomb.id), isFalse, reason: 'a found bomb goes first');
      rack.spend(kGravityBomb.id, 1);
      expect(rack.costsStar(kGravityBomb.id), isTrue);
      rack.spend(kGravityBomb.id, 1);
      expect(rack.usedCarried, isTrue);
      expect(rack.costsStar(kGravityBomb.id), isFalse, reason: 'the star is already gone');
      final gunOnly = WeaponRack(hasCannon: true);
      expect(gunOnly.costsStar(kCannon.id), isFalse);
      expect(gunOnly.costsStar(kFlak.id), isFalse);
    });

    test('a pickup selects what was picked up', () {
      final rack = WeaponRack(carried: {kFlak.id: 3});
      expect(rack.selectedId, kFlak.id);
      rack.addFound(kSeeker.id, 2);
      expect(rack.selectedId, kSeeker.id);
    });
  });

  group('in game', () {
    final h = GameHarness();
    setUpAll(h.boot);

    test('a blast wrecks the obstacle in reach and opens the rock', () async {
      final index = caveLevelWhere(
        (d) => d.spec.obstacles.any((o) => o is PendulumSpec || o is RotatingBarSpec),
      );
      await h.loadLevel(index);
      final game = h.game..debugSyncCarve = true;
      addTearDown(() => game.debugSyncCarve = false);
      final machinery = game.world.children.whereType<Wreckable>().toList();
      expect(machinery, isNotEmpty);
      final target = machinery.first;
      final wrecked = ProgressService.instance.getStat(ProgressService.statObstaclesWrecked);
      game.detonate(target.body.position.clone(), kDemoCharge);
      expect(target.destroyed, isTrue);
      expect(target.isRemoving || target.isRemoved, isTrue);
      expect(ProgressService.instance.getStat(ProgressService.statObstaclesWrecked), wrecked + 1);
    });

    test('the cannon bounces off machinery', () async {
      final index = caveLevelWhere((d) => d.spec.obstacles.any((o) => o is RotatingBarSpec));
      await h.loadLevel(index);
      final bar = h.game.world.children.whereType<RotatingBar>().first;
      for (var i = 0; i < 20; i++) {
        bar.takeHit();
      }
      expect(bar.destroyed, isFalse);
      bar.takeHit(damage: 2, heavy: true);
      expect(bar.destroyed, isFalse);
      bar.takeHit(damage: 2, heavy: true);
      expect(bar.destroyed, isTrue);
    });

    test('a charge carves rock next to the ship', () async {
      final index = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(index);
      final game = h.game..debugSyncCarve = true;
      addTearDown(() => game.debugSyncCarve = false);
      final terrain = game.world.children.whereType<CaveTerrain>().single;
      final before = terrain.loops;
      // Against the nearest wall below the spawn pad's guard: a point in the
      // rock right of the ship.
      final p = game.ship!.body.position.clone()..x += 2.5;
      game.detonate(p, kDemoCharge);
      expect(identical(terrain.loops, before), isFalse, reason: 'rock not re-extracted');
    });

    test('a charge carves rock on the background isolate too', () async {
      final index = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(index);
      final game = h.game..debugSyncCarve = false;
      final terrain = game.world.children.whereType<CaveTerrain>().single;
      final before = terrain.loops;
      final p = game.ship!.body.position.clone()..x += 2.5;
      final errors = <Object>[];
      final sink = ErrorReporter.sink;
      ErrorReporter.sink = (e, st, context) => errors.add(e);
      try {
        game.detonate(p, kDemoCharge);
        for (var i = 0; i < 100 && identical(terrain.loops, before) && errors.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      } finally {
        ErrorReporter.sink = sink;
      }
      expect(errors, isEmpty);
      expect(identical(terrain.loops, before), isFalse, reason: 'rock not re-extracted');
    });

    test('carried ammo caps the run at 2★; found ammo does not', () async {
      final index = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await ProgressService.instance.addAmmo(kFlak.id, 2);
      addTearDown(() => ProgressService.instance
          .addAmmo(kFlak.id, -ProgressService.instance.getAmmo(kFlak.id)));
      await h.loadLevel(index);
      final game = h.game;
      final rack = game.weaponRack!;
      expect(rack.ammo(kFlak.id), 2);
      expect(game.debugStars(1, 1), 3);
      rack.addFound(kGravityBomb.id, 1);
      rack.spend(kGravityBomb.id, 1);
      expect(game.debugStars(1, 1), 3);
      rack.spend(kFlak.id, 1);
      expect(game.debugStars(1, 1), 2);
      // Spent carried ammo comes off the save when the level ends.
      await h.loadLevel(index);
      expect(ProgressService.instance.getAmmo(kFlak.id), 1);
    });

    test('the ammo rail and number keys load a weapon', () async {
      final index = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await ProgressService.instance.addAmmo(kSeeker.id, 2);
      await ProgressService.instance.addAmmo(kGravityBomb.id, 3);
      addTearDown(() async {
        await ProgressService.instance.addAmmo(kSeeker.id, -2);
        await ProgressService.instance.addAmmo(kGravityBomb.id, -3);
      });
      await h.loadLevel(index);
      final game = h.game;
      final rack = game.weaponRack!;
      final ids = rack.available;
      expect(ids, containsAll([kSeeker.id, kGravityBomb.id]));
      game.selectWeapon(kSeeker.id);
      expect(rack.selectedId, kSeeker.id);
      game.selectWeapon(kMiningLaser.id);
      expect(rack.selectedId, kSeeker.id, reason: 'no laser on board');
      game.selectWeaponSlot(ids.indexOf(kGravityBomb.id));
      expect(rack.selectedId, kGravityBomb.id);
      game.selectWeaponSlot(5);
      expect(rack.selectedId, kGravityBomb.id, reason: 'an empty slot does nothing');
    });

    test('supply crates: only with an unarmed ship, never for the bot', () async {
      final game = h.game;
      addTearDown(() => game
        ..debugNoCrates = true
        ..crateRng = math.Random());
      final unarmed = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(unarmed);
      expect(game.supplyCrate, isNull, reason: 'harness turns crates off');
      // Loaded dice: every roll hits.
      game
        ..debugNoCrates = false
        ..crateRng = _LoadedDice();
      await game.loadCurrentLevel(retry: true);
      await game.ready();
      expect(game.supplyCrate, isA<SupplyCrate>(), reason: 'unarmed ship gets one');
      final armed = caveLevelWhere((d) => d.spec.id.startsWith('redoubt_'));
      game.levelIndex = armed;
      await game.loadCurrentLevel();
      await game.ready();
      expect(game.supplyCrate, isNull, reason: 'the Talon has its gun');
    });

    test('a crate\'s FIRE plate shows the first time per weapon only', () async {
      final game = h.game;
      addTearDown(() => game
        ..debugNoCrates = true
        ..crateRng = math.Random());
      final mine01 = caveLevelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(mine01);
      game
        ..debugNoCrates = false
        ..crateRng = _LoadedDice();
      await game.loadCurrentLevel(retry: true);
      await game.ready();
      final crate = game.supplyCrate!;
      final id = crate.weapon.id;
      expect(ProgressService.instance.crateHintSeen(id), isFalse);
      game.debugCollectCrate(crate);
      expect(game.debugCrateNotice?.kind, crate.weapon.kind);
      expect(ProgressService.instance.crateHintSeen(id), isTrue);
      // The same weapon again: the icon flies in, no plate.
      await h.loadLevel(mine01);
      expect(game.debugCrateNotice, isNull);
      game.debugCollectCrate(crate);
      expect(game.debugCrateNotice, isNull);
    });
  });
}

/// Crate dice that always roll a crate (and the first spot and weapon).
class _LoadedDice implements math.Random {
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}
