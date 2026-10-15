// tut_01's flight drills and the nose-down lesson, in the real game.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/guidance/flight_drills.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

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

  test('FIRE is coached a few seconds, once ever', () async {
    final g = h.game;
    final level = caveLevelWhere(
      (d) => d.spec.obstacles.any((o) => o is TurretSpec),
    );
    expect(ProgressService.instance.fireHintSeen, isFalse);
    await h.loadLevel(level);
    await h.step(1);
    expect(g.debugCoachMark?.target, CoachTarget.fire);
    await h.step(7 * 60);
    expect(g.debugCoachMark, isNull, reason: 'its seconds are up');
    expect(ProgressService.instance.fireHintSeen, isTrue);

    await h.loadLevel(level);
    await h.step(1);
    expect(g.debugCoachMark, isNull, reason: 'shown once already');
  });

  test('THRUST / STEER are taught once, not again on tut_02', () async {
    final g = h.game;
    await h.loadLevel(0);
    // A slow turn on the pad, then a short burn.
    await h.fly(
      (f) => BotInput(rotate: f < 36 ? 0.5 : 0, thrust: f >= 36),
      maxSeconds: 1.4,
    );
    expect(g.runState, RunState.playing);
    expect(ProgressService.instance.controlsHintSeen, isTrue);

    await h.loadLevel(1);
    await h.step(1);
    expect(g.debugCoachMark, isNull);
  });
}
