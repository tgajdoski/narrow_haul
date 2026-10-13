import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/course_metrics.dart';

import 'helpers/caves.dart';

CourseMetrics _metrics({
  double length = 30,
  double minMargin = 0.7,
  double squeeze = 0,
  int gates = 0,
  int turrets = 0,
  double gravityMul = 1,
}) =>
    CourseMetrics(
      length: length,
      minMargin: minMargin,
      squeezeMeters: squeeze,
      towSqueezeMeters: 0,
      turnQuarters: 3,
      sweepMeters: gates * 3.0,
      timingGates: gates,
      turretsOnRoute: turrets,
      fieldMeters: 0,
      gravityMul: gravityMul,
      cargoMul: 1,
      slippery: false,
      liftRatio: 3,
      fuelFraction: 0.2,
    );

WorldCurve _world(String name, List<double> scores) =>
    (world: name, levels: [for (final (k, s) in scores.indexed) ('${name}_$k', s)]);

void main() {
  group('completionScore', () {
    test('tighter, longer, timed and heavier routes score higher', () {
      final easy = completionScore(_metrics());
      expect(completionScore(_metrics(minMargin: 0.35, squeeze: 10)), greaterThan(easy));
      expect(completionScore(_metrics(length: 60)), greaterThan(easy));
      expect(completionScore(_metrics(gates: 2)), greaterThan(easy));
      expect(completionScore(_metrics(turrets: 2)), greaterThan(easy));
      expect(completionScore(_metrics(gravityMul: 1.6)), greaterThan(easy));
    });

    test('bot failures and waiting add to it, and it stays in 0–100', () {
      final m = _metrics(minMargin: 0.2, squeeze: 50, length: 200, gates: 5, turrets: 5, gravityMul: 2);
      final clean = completionScore(m, bot: (profilesOk: 4, profiles: 4, heldSeconds: 0, exposedSeconds: 0));
      final hard = completionScore(m, bot: (profilesOk: 1, profiles: 4, heldSeconds: 12, exposedSeconds: 20));
      expect(hard, greaterThan(clean));
      expect(hard, lessThanOrEqualTo(100));
      expect(completionScore(_metrics()), greaterThanOrEqualTo(0));
    });
  });

  group('curveFlags', () {
    test('a rising sawtooth passes', () {
      expect(
        curveFlags([
          _world('a', [10, 14, 18, 22, 30]),
          _world('b', [20, 24, 23, 30, 38]),
        ]),
        isEmpty,
      );
    });

    test('flags a hard opener, a deep dip, a soft finale and an easier world', () {
      final flags = curveFlags([
        _world('a', [55, 30, 50, 20, 34, 45, 60, 35]),
        _world('b', [10, 12, 15, 16, 18]),
      ]);
      expect(flags.any((f) => f.contains('opener a_0')), isTrue);
      expect(flags.any((f) => f.contains('a_2 (50) → a_3 (20)')), isTrue);
      expect(flags.any((f) => f.contains('finale a_7')), isTrue);
      expect(flags.any((f) => f.contains('b: median')), isTrue);
      expect(flags.any((f) => f.contains('b: peak')), isTrue);
      expect(flags.any((f) => f.contains('drops far below')), isTrue);
    });

    test('a small wobble is noise, not a dip', () {
      expect(curveFlags([_world('a', [10, 20, 18, 30, 29, 40])]), isEmpty);
    });
  });

  test('every cave level has a measurable course', () async {
    await prebuildAllCaves();
    for (final def in allCaveDefs) {
      final m = measureCourse(def.spec, ship: shipOfCave(def));
      expect(m, isNotNull, reason: def.saveId);
      expect(m!.length, greaterThan(5), reason: def.saveId);
      final s = completionScore(m);
      expect(s, inInclusiveRange(0, 100), reason: def.saveId);
    }
  });
}
