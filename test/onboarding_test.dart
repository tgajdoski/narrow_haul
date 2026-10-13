import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/guidance/crash_tip.dart';
import 'package:narrow_haul/game/guidance/flight_drills.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/route/crash_streak.dart';

/// Gentle first flights: tut_01's drill rings, the nose-down lesson, the
/// crash screen's advice and earlier route help in Training.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const step = 1 / 60;

  DrillShip at(double x, double y, {double speed = 0, double tilt = 0, bool launched = true}) =>
      DrillShip(pos: Pt(x, y), speed: speed, tiltDeg: tilt, launched: launched);

  /// Runs [seconds] of frames, returning the events.
  List<DrillEvent> fly(DrillCourse c, double seconds, DrillShip ship) => [
        for (var t = 0.0; t < seconds; t += step)
          ?c.update(step, ship),
      ];

  group('flight drills', () {
    final points = [const Pt(4, 4), const Pt(12, 4), const Pt(16, 12.3)];

    test('a hover, a fly-through, then a landing', () {
      final c = DrillCourse(points);
      expect([for (final s in c.steps) s.kind],
          [DrillKind.hold, DrillKind.reach, DrillKind.land]);
      expect(c.view?.number, 1);
      expect(c.view?.count, 3);
    });

    test('nothing counts on the pad before launch', () {
      final c = DrillCourse(points);
      expect(fly(c, 3, at(4, 4, launched: false)), isEmpty);
      expect(c.index, 0);
    });

    test('the hover ring needs a steady second inside', () {
      final c = DrillCourse(points);
      expect(fly(c, 0.5, at(4, 4)), isEmpty);
      expect(c.view!.progress, closeTo(0.5, 0.05));
      // Drifting out drains it slowly, not to zero.
      fly(c, 0.2, at(8, 4));
      expect(c.view!.progress, greaterThan(0.3));
      expect(fly(c, 0.8, at(4.5, 4.5)), [DrillEvent.stepDone]);
      expect(c.index, 1);
    });

    test('a landing counts only at rest and upright', () {
      final c = DrillCourse(points, start: 2);
      expect(fly(c, 2, at(16, 12.3, speed: 1.2)), isEmpty, reason: 'still moving');
      expect(fly(c, 2, at(16, 12.3, tilt: 60)), isEmpty, reason: 'on its side');
      expect(fly(c, 1, at(16.5, 12.3)), [DrillEvent.finished]);
      expect(c.done, isTrue);
      expect(c.skipped, isFalse);
    });

    test('a retry carries on from the step reached', () {
      final c = DrillCourse(points, start: 1);
      expect(c.view?.number, 2);
      expect(fly(c, step, at(12, 4)), [DrillEvent.stepDone]);
    });

    test('a step that takes too long ends the drills gently', () {
      final c = DrillCourse(points);
      final events = fly(c, DrillCourse.stepTimeout + 1, at(30, 4));
      expect(events, [DrillEvent.skipped]);
      expect(c.done, isTrue);
      expect(c.view, isNull);
    });

    test('tut_01 has three drill markers, in order', () async {
      final data = await loadLevelFromTmx('assets/tiles/level_01.tmx', levelIndex: 0);
      expect(data.drills.length, 3);
      expect(data.drills.first.y, lessThan(data.shipSpawn.y), reason: 'hover above the start');
      expect(data.drills[1].x, greaterThan(data.drills.first.x));
      // The landing ring sits on the floor (the bottom wall's top edge).
      final floorTop = data.worldSize.y - 1;
      expect(floorTop - data.drills.last.y, inInclusiveRange(0.2, 1.2));
    });

    test('a drill ring hides the pod and canister markers until it ends', () {
      const view = DrillView(
        kind: DrillKind.hold,
        center: Pt(4, 4),
        radius: 1.5,
        label: 'HOLD HERE',
        progress: 0,
        inside: false,
        number: 1,
        count: 3,
      );
      const taught = GuidanceInputs(
        tutorial: true,
        thrustUsed: 1,
        rotateUsed: 1,
        canisterUnseen: true,
      );
      final drilling = resolveGuidance(const GuidanceInputs(
        tutorial: true,
        thrustUsed: 1,
        rotateUsed: 1,
        canisterUnseen: true,
        drill: view,
      ));
      expect(drilling.drill, same(view));
      expect(drilling.pod, isNull);
      expect(drilling.markCanister, isFalse);
      final after = resolveGuidance(taught);
      expect(after.pod, PodTag.hook);
      expect(after.markCanister, isTrue);
    });
  });

  group('nose-down watch', () {
    bool run(NoseDownWatch w, double seconds,
        {required double tilt, bool thrust = false, double down = 0}) {
      var started = false;
      for (var t = 0.0; t < seconds; t += step) {
        started |= w.update(step, tiltDeg: tilt, thrusting: thrust, downSpeed: down);
      }
      return started;
    }

    test('warns when the nose stays down under thrust', () {
      final w = NoseDownWatch();
      expect(run(w, 0.3, tilt: 130, thrust: true), isFalse, reason: 'a brief roll is fine');
      expect(run(w, 0.2, tilt: 130, thrust: true), isTrue);
      expect(w.warning, isTrue);
      expect(w.warnings, 1);
    });

    test('warns when falling nose-down, not when coasting level or sideways', () {
      expect(run(NoseDownWatch(), 1, tilt: 140, down: 2), isTrue);
      expect(run(NoseDownWatch(), 1, tilt: 140), isFalse, reason: 'drifting, not heading in');
      expect(run(NoseDownWatch(), 1, tilt: 90, thrust: true), isFalse, reason: 'sideways is a bank');
    });

    test('clears once the nose is back near up, and counts each warning', () {
      final w = NoseDownWatch();
      run(w, 1, tilt: 150, thrust: true);
      run(w, 0.5, tilt: 90, thrust: true);
      expect(w.warning, isTrue, reason: 'not yet back within the clear tilt');
      run(w, step, tilt: 40, thrust: true);
      expect(w.warning, isFalse);
      run(w, 1, tilt: 150, thrust: true);
      expect(w.warnings, 2);
      w.reset();
      expect(w.warnings, 0);
    });
  });

  group('crash advice', () {
    test('nose-down beats every other rock crash', () {
      expect(
        classifyCrash(cause: 'wall', rock: true, tiltDeg: 150, groundCos: 1),
        CrashKind.noseDown,
      );
    });

    test('floor, wall or ceiling by the slope of the rock', () {
      expect(classifyCrash(cause: 'wall', rock: true, tiltDeg: 10, groundCos: 0.95),
          CrashKind.hardLanding);
      expect(classifyCrash(cause: 'wall', rock: true, tiltDeg: 60, groundCos: 0.1),
          CrashKind.wallHit);
      expect(classifyCrash(cause: 'wall', rock: true, tiltDeg: 20, groundCos: -1),
          CrashKind.wallHit);
    });

    test('machinery, shells and meltdowns keep their own cause', () {
      expect(classifyCrash(cause: 'wall', rock: false, tiltDeg: 170, groundCos: 0),
          CrashKind.machinery);
      expect(classifyCrash(cause: 'shot', rock: true, tiltDeg: 170, groundCos: 0),
          CrashKind.shot);
      expect(classifyCrash(cause: 'meltdown', rock: true, tiltDeg: 0, groundCos: 1),
          CrashKind.meltdown);
    });

    test('every kind has short advice', () {
      for (final k in CrashKind.values) {
        expect(crashTip(k), isNotEmpty);
        expect(crashTip(k).length, lessThanOrEqualTo(110), reason: k.name);
      }
    });
  });

  test('Training offers the route after two crashes, other worlds after three', () {
    final s = CrashStreak()
      ..onCrash('tut_04')
      ..onCrash('tut_04');
    expect(s.shouldOfferFor('tut_04', training: true), isTrue);
    expect(s.shouldOfferFor('tut_04'), isFalse);
    s.onCrash('tut_04');
    expect(s.shouldOfferFor('tut_04'), isTrue);
  });
}
