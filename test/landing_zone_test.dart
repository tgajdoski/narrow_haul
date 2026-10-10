// ignore_for_file: invalid_use_of_internal_member
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_constants.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

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
    await h.loadLevel(levelIndexOf('mine_01'));
    placeOnPad(h.game);
    await h.step(30);
    expect(h.game.runState, RunState.won);
  });

  test('a landing refused mid-crash re-arms the pad', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    final game = h.game;
    // As if the ship had just crashed: the wreck slides onto the pad.
    game.runState = RunState.gameOver;
    placeOnPad(game);
    await h.step(30);
    final zone = game.debugLandingZone!;
    expect(zone.shipInside && zone.cargoInside, isTrue);
    expect(game.runState, RunState.gameOver);
    // "Continue": back in flight, the pad still takes the delivery.
    game.runState = RunState.playing;
    zone
      ..reset()
      ..recheck();
    await h.step(2);
    expect(game.runState, RunState.won);
  });

  test('the ship counts as inside while any hull piece is', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    final game = h.game;
    expect(game.ship!.body.fixtures.where((f) => !f.isSensor).length, greaterThan(1));
    placeOnPad(game);
    game.cargo!.body.setTransform(Vector2(1, 1), 0); // pod far away
    await h.step(30);
    final zone = game.debugLandingZone!;
    expect(zone.shipInside, isTrue);
    expect(zone.cargoInside, isFalse);
    expect(game.runState, RunState.playing);
  });
}
