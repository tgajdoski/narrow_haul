// ignore_for_file: invalid_use_of_internal_member
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

/// Expeditions: several hauls in one cave, staging pads between them
/// (docs/STORY.md §3).
void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  final expeditions = [
    for (final def in LevelRegistry.flat)
      if (def is CaveLevelDef && def.spec.isExpedition) def,
  ];

  /// Sets ship and the leg's pod down on the leg's pad floor, at rest.
  void landLeg(NarrowHaulGame game) {
    final pad = game.currentLeg!;
    final floorY = pad.goalCenter.y + pad.goalHalfHeight + kPadFloorDrop;
    final ship = game.ship!..launch();
    ship.body
      ..setTransform(Vector2(pad.goalCenter.x, floorY - ship.rearLocalY - 0.02), 0)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    game.cargo!.body
      ..setTransform(Vector2(pad.goalCenter.x + 0.9, floorY - CargoBody.radius - 0.01), 0)
      ..linearVelocity.setZero()
      ..setAwake(true);
  }

  test('every Expedition is in the Expeditions world, outside the career', () {
    expect(expeditions, isNotEmpty);
    for (final def in expeditions) {
      final (world, _) = LevelRegistry.worldOf(levelIndexOf(def.saveId));
      expect(world.expedition, isTrue, reason: def.saveId);
      expect(LevelRegistry.career, isNot(contains(def)));
    }
    expect(LevelRegistry.careerLevels, 60);
  });

  test('a leg is validated as one haul from the previous pad', () {
    final spec = expeditions.first.spec;
    final leg2 = spec.forLeg(1);
    expect(leg2.goal, same(spec.legs[1].goal));
    expect(leg2.shipSpawn.x, legShipSpawn(spec.legs[0].goal).x);
    expect(leg2.cargoClamped, isTrue, reason: 'later pods wait locked');
    expect(analyzeLegs(spec, ship: kHopper), hasLength(spec.legs.length));
    expect(analyzeLegs(spec, ship: kHopper).every((f) => f != null), isTrue);
  });

  test('landing a leg refuels, parks the pod and moves on; the last pad wins', () async {
    final def = expeditions.first;
    await h.loadLevel(levelIndexOf(def.saveId));
    final game = h.game;
    final legs = def.spec.legs.length;
    expect(game.legCount, legs);
    expect(game.legIndex, 0);

    for (var k = 0; k < legs - 1; k++) {
      final delivered = game.cargo!;
      final next = game.currentLevel!.legs[k + 1];
      game.ship!.fuel = game.ship!.maxFuel * 0.5;
      landLeg(game);
      await h.step(30);
      expect(game.runState, RunState.playing, reason: 'leg ${k + 1} is not the end');
      expect(game.legIndex, k + 1);
      expect(game.ship!.fuel, game.ship!.maxFuel, reason: 'the pad refuels');
      expect(delivered.body.bodyType, BodyType.kinematic, reason: 'parked');
      expect(game.cargo, isNot(same(delivered)));
      expect(game.cargo!.body.position.distanceTo(next.cargoSpawn), lessThan(0.05));
      expect(game.cargoAttachment!.attached, isFalse);
      expect(game.canResumeFromPad, isTrue);
      expect(game.checkpointPad, k + 1);
    }

    game.ship!.fuel = game.ship!.maxFuel * 0.5;
    landLeg(game);
    await h.step(30);
    expect(game.runState, RunState.won);
    // Fuel is rated over every pad: half a tank each time.
    expect(game.lastLevelFuelFraction, closeTo(0.5, 0.02));
  });

  test('a crash after a pad resumes from it, capped at 2★', () async {
    final def = expeditions.first;
    await h.loadLevel(levelIndexOf(def.saveId));
    final game = h.game;
    game.ship!.launch();
    await h.step(20); // the clock runs from launch
    landLeg(game);
    await h.step(30);
    expect(game.legIndex, 1);
    await h.step(60);
    final clock = game.elapsedSeconds;

    game.runState = RunState.gameOver;
    await game.resumeFromPad();
    await h.step(1);
    expect(game.legIndex, 1);
    expect(game.checkpointUsedThisRun, isTrue);
    expect(game.elapsedSeconds, lessThanOrEqualTo(clock));
    expect(game.elapsedSeconds, greaterThan(0));
    final start = game.currentLevel!.legs[1].startSpawn;
    expect(game.ship!.body.position.distanceTo(start), lessThan(0.3));
    expect(game.cargo!.body.position.distanceTo(game.currentLevel!.legs[1].cargoSpawn), lessThan(0.05));

    // A plain restart starts the Expedition over.
    await game.restartLevel();
    await h.step(1);
    expect(game.legIndex, 0);
    expect(game.checkpointUsedThisRun, isFalse);
    expect(game.canResumeFromPad, isFalse);
  });

  test('one-haul missions are unchanged: one leg, no checkpoint', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    final game = h.game;
    expect(game.legCount, 1);
    expect(game.isExpeditionRun, isFalse);
    landLeg(game);
    await h.step(30);
    expect(game.runState, RunState.won);
    expect(game.canResumeFromPad, isFalse);
  });

  test('the demo flight replays every leg, pod by pod', () async {
    final def = expeditions.first;
    await ProgressService.instance.setRouteUnlocked(def.saveId);
    await h.loadLevel(levelIndexOf(def.saveId));
    final g = h.game;
    g.onShipShot(); // a crash: the game-over screen offers the demo
    await g.startDemoFlight();
    await g.ready();
    expect(g.demoMode, isTrue);
    final route = g.currentRoute!;
    expect(route.legT, hasLength(def.spec.legs.length - 1));
    final r = await h.fly((_) => BotInput.idle, maxSeconds: (route.endT + 1) / g.legCount);
    expect(r.outcome, FlightOutcome.timedOut, reason: 'a demo never crashes or delivers');
    expect(g.legIndex, def.spec.legs.length - 1, reason: 'every staging pad passed');
    final last = g.currentLevel!.legs.last;
    expect(g.cargo!.body.position.distanceTo(last.goalCenter), lessThan(3));
    await g.takeControlsFromDemo();
    await g.ready();
    expect(g.demoMode, isFalse);
    expect(g.legIndex, 0);
  });
}
