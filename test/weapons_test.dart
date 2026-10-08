// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cave_terrain.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

import 'autopilot/harness.dart';

int _levelWhere(bool Function(CaveLevelDef def) test) {
  for (int i = 0; i < LevelRegistry.totalLevels; i++) {
    final def = LevelRegistry.defAt(i);
    if (def is CaveLevelDef && test(def)) return i;
  }
  throw StateError('no such level');
}

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
      final index = _levelWhere(
        (d) => d.spec.obstacles.any((o) => o is PendulumSpec || o is RotatingBarSpec),
      );
      await h.loadLevel(index);
      final game = h.game..debugSyncCarve = true;
      final machinery = game.world.children.whereType<Wreckable>().toList();
      expect(machinery, isNotEmpty);
      final target = machinery.first;
      game.detonate(target.body.position.clone(), kDemoCharge);
      expect(target.destroyed, isTrue);
      expect(target.isRemoving || target.isRemoved, isTrue);
      expect(ProgressService.instance.getStat(ProgressService.statObstaclesWrecked), 1);
    });

    test('the cannon bounces off machinery', () async {
      final index = _levelWhere((d) => d.spec.obstacles.any((o) => o is RotatingBarSpec));
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
      final index = _levelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(index);
      final game = h.game..debugSyncCarve = true;
      final terrain = game.world.children.whereType<CaveTerrain>().single;
      final before = terrain.loops;
      // Against the nearest wall below the spawn pad's guard: a point in the
      // rock right of the ship.
      final p = game.ship!.body.position.clone()..x += 2.5;
      game.detonate(p, kDemoCharge);
      expect(identical(terrain.loops, before), isFalse, reason: 'rock not re-extracted');
    });

    test('carried ammo caps the run at 2★; found ammo does not', () async {
      final index = _levelWhere((d) => d.spec.id == 'mine_01');
      await ProgressService.instance.addAmmo(kFlak.id, 2);
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

    test('supply crates: only with an unarmed ship, never for the bot', () async {
      final unarmed = _levelWhere((d) => d.spec.id == 'mine_01');
      await h.loadLevel(unarmed);
      expect(h.game.supplyCrate, isNull, reason: 'harness turns crates off');
      h.game.debugNoCrates = false;
      // Force the dice: a fresh load with a crate.
      for (var tries = 0; tries < 40 && h.game.supplyCrate == null; tries++) {
        h.game.debugNoCrates = false;
        await h.game.loadCurrentLevel(retry: true);
        await h.game.ready();
      }
      final crate = h.game.supplyCrate;
      expect(crate, isNotNull);
      expect(crate, isA<SupplyCrate>());
    });
  });
}
