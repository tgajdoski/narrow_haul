import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/perf/frame_stats.dart';

void main() {
  test('percentiles, max and over-budget counts', () {
    final s = FrameStats();
    for (var i = 1; i <= 100; i++) {
      s.add(i.toDouble());
    }
    expect(s.percentile(50), 50);
    expect(s.percentile(95), 95);
    expect(s.percentile(100), 100);
    expect(s.max, 100);
    expect(s.mean, closeTo(50.5, 1e-9));
    expect(s.countOver(16.7), 84);
  });

  test('keeps only the last capacity values, totals everything', () {
    final s = FrameStats(capacity: 4);
    for (final v in <double>[100, 1, 2, 3, 4]) {
      s.add(v);
    }
    expect(s.length, 4);
    expect(s.total, 5);
    expect(s.percentile(100), 4, reason: 'the 100 ms frame fell out of the window');
    expect(s.max, 100, reason: 'max covers every value since clear');
    s.clear();
    expect(s.total, 0);
    expect(s.percentile(50), 0);
  });
}
