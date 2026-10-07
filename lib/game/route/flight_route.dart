// Recorded flights (ship + pod poses over time) for the route guide, the
// ghost ship and the demo flight. Pure Dart: shared by the game, the
// autopilot export and tests.
import 'dart:math' as math;

/// One sample of a flight, [t] seconds after the level was loaded (the
/// obstacles' clock, so a replay stays in sync with them).
class RouteSample {
  const RouteSample({
    required this.t,
    required this.x,
    required this.y,
    required this.angle,
    required this.cx,
    required this.cy,
    this.towing = false,
    this.thrust = false,
  });

  final double t;

  /// Ship position (m) and angle (rad).
  final double x;
  final double y;
  final double angle;

  /// Pod position (m).
  final double cx;
  final double cy;
  final bool towing;
  final bool thrust;

  static const int _towBit = 1;
  static const int _thrustBit = 2;

  List<num> toJson() => [
        _r(t),
        _r(x),
        _r(y),
        _r(angle, 1000),
        _r(cx),
        _r(cy),
        (towing ? _towBit : 0) | (thrust ? _thrustBit : 0),
      ];

  factory RouteSample.fromJson(List<dynamic> j) {
    final flags = (j[6] as num).toInt();
    return RouteSample(
      t: (j[0] as num).toDouble(),
      x: (j[1] as num).toDouble(),
      y: (j[2] as num).toDouble(),
      angle: (j[3] as num).toDouble(),
      cx: (j[4] as num).toDouble(),
      cy: (j[5] as num).toDouble(),
      towing: flags & _towBit != 0,
      thrust: flags & _thrustBit != 0,
    );
  }
}

/// Interpolated pose at some time of a [FlightRoute].
typedef RoutePose = ({
  double x,
  double y,
  double angle,
  double cx,
  double cy,
  bool towing,
  bool thrust,
});

/// A burst of recorded shots: where the ship was and where its nose pointed.
typedef FireMark = ({double t, double x, double y, double dirX, double dirY, int shots});

class FlightRoute {
  const FlightRoute({
    required this.saveId,
    required this.shipId,
    required this.samples,
    required this.launchT,
    required this.attachT,
    required this.seconds,
    this.stars = 0,
    this.fuelLeft = 0,
    this.shots = const [],
    this.shotRays = const [],
  });

  static const int version = 1;

  final String saveId;
  final String shipId;

  /// Samples every [FlightRecorder.sampleEvery] s from level load to delivery.
  final List<RouteSample> samples;

  /// Time of the first input (the level clock starts here).
  final double launchT;

  /// Time the rope attached (null: never).
  final double? attachT;

  /// Level clock at delivery (from launch, like `elapsedSeconds`).
  final double seconds;
  final int stars;
  final double fuelLeft;

  /// Times the (armed) ship fired.
  final List<double> shots;

  /// Per shot (when recorded): muzzle x, y and shell velocity x, y — the
  /// demo fires exactly these. Empty in older recordings.
  final List<List<double>> shotRays;

  double get endT => samples.isEmpty ? 0 : samples.last.t;

  /// Where the recorded flight fired: one mark per burst (shots less than
  /// 1 s apart), at the ship's position, with the nose direction.
  List<FireMark> fireMarks() {
    final out = <FireMark>[];
    double? burstStart;
    var count = 0;
    var burstIdx = 0;
    void flush() {
      final t = burstStart;
      if (t == null) return;
      final p = poseAt(t);
      var dx = math.sin(p.angle);
      var dy = -math.cos(p.angle);
      if (burstIdx < shotRays.length) {
        final r = shotRays[burstIdx];
        final len = math.sqrt(r[2] * r[2] + r[3] * r[3]);
        if (len > 1e-6) {
          dx = r[2] / len;
          dy = r[3] / len;
        }
      }
      out.add((t: t, x: p.x, y: p.y, dirX: dx, dirY: dy, shots: count));
    }

    double? last;
    for (final (i, t) in shots.indexed) {
      if (last == null || t - last > 1.0) {
        flush();
        burstStart = t;
        burstIdx = i;
        count = 0;
      }
      count++;
      last = t;
    }
    flush();
    return out;
  }

  /// Samples from launch on (the part a player flies).
  Iterable<RouteSample> get flown => samples.where((s) => s.t >= launchT);

  /// Pose at [t] (clamped to the recording): Catmull-Rom through the
  /// samples for positions, shortest-arc lerp for the angle; flags from the
  /// sample at or before [t].
  RoutePose poseAt(double t) {
    final n = samples.length;
    if (n == 0) {
      return (x: 0, y: 0, angle: 0, cx: 0, cy: 0, towing: false, thrust: false);
    }
    if (n == 1 || t <= samples.first.t) return _pose(samples.first);
    if (t >= samples.last.t) return _pose(samples.last);
    // Binary search for the segment [i, i + 1] containing t.
    var lo = 0;
    var hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (samples[mid].t <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = samples[lo];
    final b = samples[hi];
    final p0 = samples[math.max(0, lo - 1)];
    final p3 = samples[math.min(n - 1, hi + 1)];
    final span = b.t - a.t;
    final u = span <= 0 ? 0.0 : (t - a.t) / span;
    var da = (b.angle - a.angle) % (2 * math.pi);
    if (da > math.pi) da -= 2 * math.pi;
    return (
      x: _catmull(p0.x, a.x, b.x, p3.x, u),
      y: _catmull(p0.y, a.y, b.y, p3.y, u),
      angle: a.angle + da * u,
      cx: _catmull(p0.cx, a.cx, b.cx, p3.cx, u),
      cy: _catmull(p0.cy, a.cy, b.cy, p3.cy, u),
      towing: a.towing,
      thrust: a.thrust,
    );
  }

  static RoutePose _pose(RouteSample s) => (
        x: s.x,
        y: s.y,
        angle: s.angle,
        cx: s.cx,
        cy: s.cy,
        towing: s.towing,
        thrust: s.thrust,
      );

  static double _catmull(double p0, double p1, double p2, double p3, double u) {
    final u2 = u * u;
    final u3 = u2 * u;
    return 0.5 *
        (2 * p1 +
            (-p0 + p2) * u +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * u3);
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'id': saveId,
        'ship': shipId,
        'launchT': _r(launchT),
        'attachT': attachT == null ? null : _r(attachT!),
        'seconds': _r(seconds),
        'stars': stars,
        'fuelLeft': _r(fuelLeft, 1000),
        'shots': [for (final s in shots) _r(s)],
        if (shotRays.isNotEmpty) 'shotRays': [for (final r in shotRays) [for (final v in r) _r(v, 1000)]],
        'pts': [for (final s in samples) s.toJson()],
      };

  factory FlightRoute.fromJson(Map<String, dynamic> j) {
    final v = (j['v'] as num?)?.toInt() ?? 0;
    if (v != version) throw FormatException('route version $v != $version');
    return FlightRoute(
      saveId: j['id'] as String,
      shipId: j['ship'] as String,
      launchT: (j['launchT'] as num).toDouble(),
      attachT: (j['attachT'] as num?)?.toDouble(),
      seconds: (j['seconds'] as num).toDouble(),
      stars: (j['stars'] as num?)?.toInt() ?? 0,
      fuelLeft: (j['fuelLeft'] as num?)?.toDouble() ?? 0,
      shots: [for (final s in (j['shots'] as List? ?? const [])) (s as num).toDouble()],
      shotRays: [
        for (final r in (j['shotRays'] as List? ?? const []))
          [for (final v in r as List) (v as num).toDouble()],
      ],
      samples: [for (final p in j['pts'] as List) RouteSample.fromJson(p as List)],
    );
  }
}

/// Builds a [FlightRoute] while a level is flown. The game feeds it every
/// frame; it keeps one sample per [sampleEvery] seconds of level time.
class FlightRecorder {
  FlightRecorder({required this.saveId, required this.shipId});

  static const double sampleEvery = 0.1;

  final String saveId;
  final String shipId;

  final List<RouteSample> _samples = [];
  final List<double> _shots = [];
  final List<List<double>> _shotRays = [];

  /// Level time (s since load), advanced by [tick].
  double time = 0;
  double _nextSample = 0;
  double? _launchT;
  double? _attachT;

  /// Advances the clock by [dt] and records the state if a sample is due.
  void tick(
    double dt, {
    required double x,
    required double y,
    required double angle,
    required double cx,
    required double cy,
    required bool launched,
    required bool towing,
    required bool thrust,
  }) {
    time += dt;
    if (launched) _launchT ??= time;
    if (towing) _attachT ??= time;
    if (time + 1e-9 < _nextSample) return;
    _nextSample += sampleEvery;
    if (_nextSample < time) _nextSample = time + sampleEvery; // after a hitch
    _add(x, y, angle, cx, cy, towing, thrust);
  }

  /// The (armed) ship fired; [ray] = muzzle x, y and shell velocity x, y,
  /// so a demo can fire the very same shell.
  void shot([List<double>? ray]) {
    _shots.add(time);
    if (ray != null && _shotRays.length == _shots.length - 1) _shotRays.add(ray);
  }

  void _add(double x, double y, double angle, double cx, double cy, bool towing, bool thrust) {
    _samples.add(RouteSample(
      t: time,
      x: x,
      y: y,
      angle: angle,
      cx: cx,
      cy: cy,
      towing: towing,
      thrust: thrust,
    ));
  }

  /// The finished flight, with a closing sample at the delivery pose.
  FlightRoute finish({
    required double x,
    required double y,
    required double angle,
    required double cx,
    required double cy,
    required double seconds,
    required int stars,
    required double fuelLeft,
  }) {
    if (_samples.isNotEmpty && _samples.last.t >= time) _samples.removeLast();
    _add(x, y, angle, cx, cy, _attachT != null, false);
    return FlightRoute(
      saveId: saveId,
      shipId: shipId,
      samples: List.unmodifiable(_samples),
      launchT: _launchT ?? 0,
      attachT: _attachT,
      seconds: seconds,
      stars: stars,
      fuelLeft: fuelLeft,
      shots: List.unmodifiable(_shots),
      shotRays: _shotRays.length == _shots.length ? List.unmodifiable(_shotRays) : const [],
    );
  }
}

/// Rounds for compact JSON ([scale] 100 = 1 cm / 10 ms).
double _r(double v, [double scale = 100]) => (v * scale).roundToDouble() / scale;
