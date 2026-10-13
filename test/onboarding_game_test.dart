// tut_01's flight drills and the nose-down lesson, in the real game.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/guidance/flight_drills.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

import 'autopilot/harness.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  test('a fresh pilot gets the drills on tut_01, and a hover ticks the first', () async {
    final g = h.game;
    await h.loadLevel(0);
    final d = g.debugDrill;
    expect(d, isNotNull);
    expect(d!.kind, DrillKind.hold);
    expect(d.number, 1);
    // Climb to the ring and hover there: thrust while below it or sinking.
    await h.fly(
      (f) {
        final b = g.ship!.body;
        return BotInput(
          thrust: f == 0 || (b.position.y > d.center.y && b.linearVelocity.y > -0.8) ||
              b.linearVelocity.y > 0.4,
        );
      },
      maxSeconds: 6,
    );
    expect(g.runState, RunState.playing);
    expect(g.debugDrill?.kind, DrillKind.reach, reason: 'the hover ring is done');
  });

  test('upside down under thrust raises the nose-up cue', () async {
    final g = h.game;
    await h.loadLevel(0);
    await h.fly((f) => BotInput(thrust: f == 0), maxSeconds: 0.05);
    final b = g.ship!.body;
    b.setTransform(b.position, math.pi);
    expect(g.debugNoseDownWarning, isFalse);
    await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.6);
    expect(g.debugNoseDownWarning, isTrue);
  });
}
