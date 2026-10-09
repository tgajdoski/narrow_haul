import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/perf/frame_stats.dart';

/// `--dart-define=PERF=true` turns the probe on (any build mode; use
/// `--profile` on a device for real numbers). Off, every hook is a const
/// `if` the compiler drops.
const bool kPerfProbe = bool.fromEnvironment('PERF');

/// Dev-only performance probe: engine frame timings (build/raster), the
/// game's own update and render cost, level load times and startup marks.
/// Prints one `PERF …` line per flight; nothing leaves the device.
class PerfMonitor {
  PerfMonitor._();

  static final Stopwatch _clock = Stopwatch();
  static final _marks = <String, int>{};

  /// UI-thread time per engine frame (Flutter build + layout + paint).
  static final build = FrameStats();

  /// Raster-thread time per engine frame (GPU submission).
  static final raster = FrameStats();

  /// `NarrowHaulGame.update` in total (components, physics, game logic).
  static final update = FrameStats();

  /// The game's own logic after `super.update` (part of [update]).
  static final logic = FrameStats();

  /// `NarrowHaulGame.render` (recording the frame's draw calls).
  static final render = FrameStats();

  /// Per-section game logic cost ([lapStart] / [lap]), by section name.
  static final sections = <String, FrameStats>{};
  static final Stopwatch _lapClock = Stopwatch();
  static int _lapAt = 0;

  /// Starts timing a chain of [lap]s this frame.
  static void lapStart() {
    if (!sampling) return;
    _lapClock
      ..reset()
      ..start();
    _lapAt = 0;
  }

  /// Books the time since the previous lap (or [lapStart]) to [name].
  static void lap(String name) {
    if (!sampling || !_lapClock.isRunning) return;
    final now = _lapClock.elapsedMicroseconds;
    (sections[name] ??= FrameStats()).add((now - _lapAt) / 1000);
    _lapAt = now;
  }

  static double get lastLoadMs => _loadMs;

  static String? _level;
  static double _loadMs = 0;
  static bool _installed = false;

  /// Rolling FPS and worst frame over the last half second (HUD readout).
  static double fps = 0;
  static double recentWorstMs = 0;
  static double updateP95 = 0;
  static int _windowFrames = 0;
  static double _windowWorst = 0;

  /// Startup mark relative to the first [mark] call (`main`).
  static void mark(String name) {
    if (!kPerfProbe) return;
    if (!_clock.isRunning) _clock.start();
    _marks[name] = _clock.elapsedMilliseconds;
    debugPrint('PERF mark $name +${_clock.elapsedMilliseconds}ms');
  }

  static void install() {
    if (!kPerfProbe || _installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000;
      final r = t.rasterDuration.inMicroseconds / 1000;
      if (_level != null) {
        build.add(b);
        raster.add(r);
      }
      final total = t.totalSpan.inMicroseconds / 1000;
      _windowFrames++;
      if (total > _windowWorst) _windowWorst = total;
    }
  }

  /// Called by the HUD readout twice a second.
  static void rollWindow(double seconds) {
    fps = seconds > 0 ? _windowFrames / seconds : 0;
    recentWorstMs = _windowWorst;
    updateP95 = update.percentile(95);
    _windowFrames = 0;
    _windowWorst = 0;
  }

  /// Whether a flight is being sampled (between [levelLoaded] and
  /// [flightEnded]).
  static bool get sampling => kPerfProbe && _level != null;

  static void levelLoaded(String saveId, double loadMs) {
    if (!kPerfProbe) return;
    _level = saveId;
    _loadMs = loadMs;
    for (final s in [build, raster, update, logic, render]) {
      s.clear();
    }
    sections.clear();
    debugPrint('PERF load $saveId ${loadMs.toStringAsFixed(0)}ms');
  }

  /// One summary line for the flight that just ended ([outcome]: delivered,
  /// crashed, quit…). Safe to call more than once; the first call wins.
  static void flightEnded(String outcome) {
    if (!kPerfProbe) return;
    final level = _level;
    if (level == null || update.total == 0) return;
    _level = null;
    debugPrint(report(level, outcome));
  }

  /// The current flight's numbers (ms p50/p95/p99/max per series), for
  /// tests and tools.
  static Map<String, Object> toJson() {
    Map<String, double> q(FrameStats s) => {
          'p50': s.percentile(50),
          'p95': s.percentile(95),
          'p99': s.percentile(99),
          'max': s.max,
          'mean': s.mean,
        };
    return {
      'level': _level ?? '',
      'frames': update.total,
      'engineFrames': raster.total,
      'loadMs': _loadMs,
      'build': q(build),
      'raster': q(raster),
      'update': q(update),
      'logic': q(logic),
      'render': q(render),
      'jank16': _jank(16.7),
      'jank33': _jank(33.4),
      'sections': {for (final e in sections.entries) e.key: q(e.value)},
    };
  }

  static String report(String level, String outcome) =>
      'PERF $level $outcome frames=${update.total} '
      'load=${_loadMs.toStringAsFixed(0)}ms '
      'build=${build.summary()} raster=${raster.summary()} '
      'update=${update.summary()} logic=${logic.summary()} '
      'render=${render.summary()} '
      '${[for (final e in sections.entries) '${e.key}=${e.value.summary()}'].join(' ')} '
      'jank>16.7=${_jank(16.7)} jank>33=${_jank(33.4)} (ms p50/p95/p99/max)';

  /// Frames where the slower of the two threads overran [ms] (a lower
  /// bound on late frames: the threads overlap).
  static int _jank(double ms) {
    final b = build.countOver(ms), r = raster.countOver(ms);
    return b > r ? b : r;
  }
}

/// Top-left FPS readout, only added when [kPerfProbe] is on.
class PerfHud extends PositionComponent {
  PerfHud() : super(priority: 6000, position: Vector2(8, 4));

  final _text = HudText();
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= 0.5) {
      PerfMonitor.rollWindow(_t);
      _t = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    final p = _text.layout(TextSpan(
      text: '${PerfMonitor.fps.toStringAsFixed(0)} fps · worst '
          '${PerfMonitor.recentWorstMs.toStringAsFixed(0)}ms · upd p95 '
          '${PerfMonitor.updateP95.toStringAsFixed(1)}',
      style: const TextStyle(fontSize: 10, color: Color(0xFFB8FFB0)),
    ));
    p.paint(canvas, Offset.zero);
  }
}
