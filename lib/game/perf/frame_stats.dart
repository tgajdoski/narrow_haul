import 'dart:math' as math;
import 'dart:typed_data';

/// Rolling sample of per-frame timings in milliseconds (pure Dart): the
/// last [capacity] values, with percentiles and over-budget counts.
class FrameStats {
  FrameStats({this.capacity = 4096}) : _buf = Float64List(capacity);

  final int capacity;
  final Float64List _buf;
  int _next = 0;
  int _count = 0;
  int _total = 0;
  double _max = 0;
  double _sum = 0;

  /// Values seen since the last [clear] (the buffer keeps only the last
  /// [capacity] of them for percentiles).
  int get total => _total;
  int get length => _count;
  double get max => _max;
  double get mean => _total == 0 ? 0 : _sum / _total;

  void add(double ms) {
    _buf[_next] = ms;
    _next = (_next + 1) % capacity;
    if (_count < capacity) _count++;
    _total++;
    _sum += ms;
    if (ms > _max) _max = ms;
  }

  void clear() {
    _next = 0;
    _count = 0;
    _total = 0;
    _max = 0;
    _sum = 0;
  }

  /// Nearest-rank percentile over the buffered values, [p] in 0..100.
  double percentile(double p) {
    if (_count == 0) return 0;
    final sorted = Float64List.sublistView(_buf, 0, _count).toList()..sort();
    final rank = (p / 100 * _count).ceil().clamp(1, _count);
    return sorted[rank - 1];
  }

  /// Buffered values strictly above [ms].
  int countOver(double ms) {
    var n = 0;
    for (var i = 0; i < _count; i++) {
      if (_buf[i] > ms) n++;
    }
    return n;
  }

  /// `p50/p95/p99/max` in ms, one decimal.
  String summary() {
    String f(double v) => v.toStringAsFixed(v >= 10 ? 0 : 1);
    return '${f(percentile(50))}/${f(percentile(95))}/${f(percentile(99))}/'
        '${f(math.max(_max, 0))}';
  }
}
