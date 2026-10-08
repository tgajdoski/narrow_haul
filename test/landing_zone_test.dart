// ignore_for_file: invalid_use_of_internal_member
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_constants.dart';

import 'autopilot/harness.dart';

int _levelId(String id) {
  for (int i = 0; i < LevelRegistry.totalLevels; i++) {
    final def = LevelRegistry.defAt(i);
    if (def is CaveLevelDef && def.spec.id == id) return i;
  }
  throw StateError('no level $id');
}

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  Future<void> step(int frames) async {
    for (var i = 0; i < frames; i++) {
      h.game.update(kStepDt);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Sets ship and pod down on the pad's floor, at rest.
  void placeOnPad(NarrowHaulGame game) {
    final level = game.currentLevel!;
    final floorY = level.goalCenter.y + level.goalHalfHeight + kPadFloorDrop;
    final ship = game.ship!..launch();
    ship.body
      ..setTransform(Vector2(level.goalCenter.x, floorY - ship.rearLocalY - 0.02), 0)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    game.cargo!.body
      ..setTransform(Vector2(level.goalCenter.x + 0.9, floorY - CargoBody.radius - 0.01), 0)
      ..linearVelocity.setZero()
      ..setAwake(true);
  }

  test('ship and pod resting on the pad floor deliver', () async {
    await h.loadLevel(_levelId('mine_01'));
    placeOnPad(h.game);
    await step(30);
    expect(h.game.runState, RunState.won);
  });

  test('a landing refused mid-crash re-arms the pad', () async {
    await h.loadLevel(_levelId('mine_01'));
    final game = h.game;
    // As if the ship had just crashed: the wreck slides onto the pad.
    game.runState = RunState.gameOver;
    placeOnPad(game);
    await step(30);
    final zone = game.debugLandingZone!;
    expect(zone.shipInside && zone.cargoInside, isTrue);
    expect(game.runState, RunState.gameOver);
    // "Continue": back in flight, the pad still takes the delivery.
    game.runState = RunState.playing;
    zone
      ..reset()
      ..recheck();
    await step(2);
    expect(game.runState, RunState.won);
  });

  test('the ship counts as inside while any hull piece is', () async {
    await h.loadLevel(_levelId('mine_01'));
    final game = h.game;
    expect(game.ship!.body.fixtures.where((f) => !f.isSensor).length, greaterThan(1));
    placeOnPad(game);
    game.cargo!.body.setTransform(Vector2(1, 1), 0); // pod far away
    await step(30);
    final zone = game.debugLandingZone!;
    expect(zone.shipInside, isTrue);
    expect(zone.cargoInside, isFalse);
    expect(game.runState, RunState.playing);
  });
}
