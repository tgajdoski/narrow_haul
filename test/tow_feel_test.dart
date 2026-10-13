// How the tow feels: the stock cable catches from a loose hover and winches
// in, and the tractor beam is a swinging tether, not a rigid rod. The ship
// is driven kinematically so only the tow moves the pod.
import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';

import 'autopilot/autopilot.dart';
import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  Vector2 winch() => h.game.ship!.body.worldPoint(Vector2(0, h.game.ship!.rearLocalY));

  /// Pod angle off straight down (degrees, + = pod to the right of the winch).
  double podAngle() {
    final d = h.game.cargo!.body.worldCenter - winch();
    return math.atan2(d.x, d.y) * 180 / math.pi;
  }

  /// Moves the kinematic ship at [v] for [seconds].
  Future<void> drive(Vector2 v, double seconds, {void Function()? each}) async {
    final body = h.game.ship!.body;
    h.game
      ..rotateAxis = 0
      ..thrustHeld = false;
    for (var t = 0.0; t < seconds; t += kStepDt) {
      body
        ..linearVelocity = v
        ..angularVelocity = 0;
      await h.step(1);
      each?.call();
    }
  }

  test('the stock cable catches from a loose hover and winches in', () async {
    await h.loadLevel(levelIndexOf('tut_01'), skipHazards: true);
    final g = h.game;
    final ship = g.ship!;
    ship.body
      ..setType(BodyType.kinematic)
      ..angularVelocity = 0;
    // Winch 1.4 m over the pod centre: out of the old 1.09 m reach.
    final pod = g.cargo!.body.worldCenter;
    ship.body.setTransform(pod - Vector2(0, 1.4 + ship.rearLocalY), 0);
    var t = 0.0;
    while (!(g.cargoAttachment?.attached ?? false) && t < 2) {
      await drive(Vector2.zero(), kStepDt);
      t += kStepDt;
    }
    expect(g.cargoAttachment!.attached, isTrue, reason: 'no catch from 1.4 m');
    await h.step(1);
    final coupling = g.cargoAttachment!.children.whereType<RopePhysicsCoupling>().single;
    expect(coupling.tetherLengthMeters, greaterThan(1.2));
    await drive(Vector2.zero(), 1.0);
    expect(coupling.tetherLengthMeters, closeTo(g.cargoAttachment!.rope.minTowLength, 1e-6));
  });

  test('the tractor beam lags on a hard move and swings back', () async {
    CosmeticsService.trialOverride[CosmeticsService.catRope] = 'rope_tractor';
    addTearDown(CosmeticsService.clearTrials);
    final index = levelIndexOf('tut_01');
    await h.loadLevel(index, skipHazards: true);
    final g = h.game;
    final bot = Autopilot(g, h.navGrid(LevelRegistry.defAt(index)), kPilotProfiles.first);
    await h.fly(bot.step, describe: bot.describe, abort: () => g.cargoAttachment?.attached ?? false);
    expect(g.cargoAttachment?.attached, isTrue);
    final ship = g.ship!;
    ship.body
      ..setType(BodyType.kinematic)
      ..angularVelocity = 0
      ..setTransform(ship.body.position, 0);
    g.ship!.fuel = g.ship!.maxFuel;

    // Climb clear of the floor and let the pod settle under the ship.
    await drive(Vector2(0, -1.0), 1.0);
    await drive(Vector2.zero(), 6);
    expect(podAngle().abs(), lessThan(5), reason: 'pod not hanging under the ship');

    // A hard sideways push: the pod trails behind.
    var lag = 0.0;
    for (var t = 0.0; t < 0.8; t += kStepDt) {
      await drive(Vector2(t * 3.0, 0), kStepDt);
      lag = math.min(lag, podAngle());
    }
    expect(lag, lessThan(-15), reason: 'pod held rigid under a 3 m/s² push');

    // Stop dead: the pod swings past the ship, then settles.
    var swing = 0.0;
    await drive(Vector2.zero(), 6, each: () => swing = math.max(swing, podAngle()));
    expect(swing, greaterThan(5), reason: 'no swing on the stop');
    expect(podAngle().abs(), lessThan(5), reason: 'still swinging after 6 s');
    expect(g.cargoAttachment!.attached, isTrue, reason: 'beam broke');
  });
}
