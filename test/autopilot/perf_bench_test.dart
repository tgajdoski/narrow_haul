// Headless performance bench: flies every level once (one autopilot
// profile, no search) through the real game, rendering each frame into an
// offscreen canvas, and writes build/perf_report.md.
//
//   flutter test test/autopilot/perf_bench_test.dart --run-skipped \
//     --dart-define=PERF=true --dart-define=STORE_CAPTURE=true \
//     [--dart-define=LEVELS=alien_01,redoubt_03] [--dart-define=PROFILE=steady]
//
// The VM runs in JIT mode and nothing is rasterised, so the numbers compare
// levels and before/after a change; they are not phone frame times (use
// integration_test/perf_flight_test.dart in --profile on a device for those).
// What it measures, per level: load time, `update` (components + physics +
// game logic), the game-logic sections, `render` (recording draw calls, a
// CPU cost on the UI thread) and a render breakdown by component type.
@Tags(['autopilot'])
library;
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/perf/frame_stats.dart';
import 'package:narrow_haul/game/perf/perf_monitor.dart';

import 'autopilot.dart';
import 'harness.dart';

const _levels = String.fromEnvironment('LEVELS');
const _profile = String.fromEnvironment('PROFILE', defaultValue: 'steady');

/// Every [_breakdownEvery]th frame each top-level component is rendered
/// on its own and timed by type.
const _breakdownEvery = 10;

class _LevelPerf {
  _LevelPerf(this.id, this.outcome, this.frames, this.loadMs, this.update, this.logic, this.render,
      this.sections, this.byType);
  final String id;
  final String outcome;
  final int frames;
  final double loadMs;
  final FrameStats update;
  final FrameStats logic;
  final FrameStats render;
  final Map<String, FrameStats> sections;
  final Map<String, FrameStats> byType;
}

/// The monitor's stats are cleared on the next load; keep a snapshot.
FrameStats _copy(FrameStats s) => _Snapshot(s);

class _Snapshot extends FrameStats {
  _Snapshot(FrameStats s)
      : _p50 = s.percentile(50),
        _p95 = s.percentile(95),
        _p99 = s.percentile(99),
        _max = s.max,
        _mean = s.mean,
        super(capacity: 1);
  final double _p50, _p95, _p99, _max, _mean;
  @override
  double percentile(double p) => p <= 50 ? _p50 : (p <= 95 ? _p95 : _p99);
  @override
  double get max => _max;
  @override
  double get mean => _mean;
}

void main() {
  test('perf bench', () async {
    expect(kPerfProbe, isTrue, reason: 'run with --dart-define=PERF=true');
    final profile = kPilotProfiles.firstWhere((p) => p.name == _profile);
    final h = GameHarness();
    await h.boot();
    final wanted = _levels.isEmpty ? null : _levels.split(',').toSet();
    final results = <_LevelPerf>[];
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      final def = LevelRegistry.defAt(i);
      if (wanted != null && !wanted.contains(def.saveId)) continue;
      await h.loadLevel(i);
      final loadMs = PerfMonitor.lastLoadMs;
      final bot = Autopilot(h.game, h.navGrid(def), profile);
      final byType = <String, FrameStats>{};
      var frame = 0;
      final r = await h.fly(bot.step, abort: () => bot.gaveUp, afterStep: () {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        final sw = Stopwatch()..start();
        h.game.render(canvas);
        if (PerfMonitor.sampling) PerfMonitor.render.add(sw.elapsedMicroseconds / 1000);
        rec.endRecording().dispose();
        if (frame++ % _breakdownEvery == 0) _breakdown(h, byType);
      });
      results.add(_LevelPerf(
        def.saveId,
        r.outcome.name,
        PerfMonitor.update.total,
        loadMs,
        _copy(PerfMonitor.update),
        _copy(PerfMonitor.logic),
        _copy(PerfMonitor.render),
        {for (final e in PerfMonitor.sections.entries) e.key: _copy(e.value)},
        byType,
      ));
      print('${def.saveId.padRight(13)} ${r.outcome.name.padRight(9)} '
          'load ${loadMs.toStringAsFixed(0).padLeft(4)}ms  '
          'update ${PerfMonitor.update.summary()}  render ${PerfMonitor.render.summary()}');
    }
    _write(results);
  }, timeout: const Timeout(Duration(hours: 1)));
}

/// Renders each top-level world and viewport component alone into a
/// throwaway canvas, timing it by runtime type.
void _breakdown(GameHarness h, Map<String, FrameStats> byType) {
  final game = h.game;
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  void time(Component c, String prefix) {
    final sw = Stopwatch()..start();
    c.renderTree(canvas);
    (byType['$prefix${c.runtimeType}'] ??= FrameStats(capacity: 1024)).add(sw.elapsedMicroseconds / 1000);
  }

  for (final c in game.world.children) {
    time(c, '');
  }
  for (final c in game.camera.viewport.children) {
    time(c, 'hud:');
  }
  rec.endRecording().dispose();
}

void _write(List<_LevelPerf> results) {
  String ms(double v) => v.toStringAsFixed(v >= 10 ? 1 : 2);
  final b = StringBuffer()
    ..writeln('# Perf bench (headless, JIT; compare runs, not absolute)')
    ..writeln()
    ..writeln('Profile `$_profile`. ms per frame, p50 / p95 / max. Sorted by update p95 + render p95.')
    ..writeln()
    ..writeln('| level | outcome | frames | load ms | update p50 | update p95 | update max | logic p95 | render p50 | render p95 |')
    ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  final sorted = [...results]
    ..sort((a, b) => (b.update.percentile(95) + b.render.percentile(95))
        .compareTo(a.update.percentile(95) + a.render.percentile(95)));
  for (final r in sorted) {
    b.writeln('| ${r.id} | ${r.outcome} | ${r.frames} | ${r.loadMs.toStringAsFixed(0)} | '
        '${ms(r.update.percentile(50))} | ${ms(r.update.percentile(95))} | ${ms(r.update.max)} | '
        '${ms(r.logic.percentile(95))} | ${ms(r.render.percentile(50))} | ${ms(r.render.percentile(95))} |');
  }

  // Game-logic sections and render-by-type, averaged over all levels.
  void table(String title, Map<String, List<FrameStats>> rows) {
    b
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln('| part | mean ms | worst p95 ms (level) |')
      ..writeln('|---|---:|---:|');
    final entries = rows.entries.map((e) {
      final mean = e.value.map((s) => s.mean).reduce((a, b) => a + b) / e.value.length;
      return (e.key, mean, e.value);
    }).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (name, mean, list) in entries) {
      var worst = 0.0;
      var worstLevel = '';
      for (var i = 0; i < list.length; i++) {
        final p = list[i].percentile(95);
        if (p > worst) {
          worst = p;
          worstLevel = (list[i] as _Tagged).level;
        }
      }
      b.writeln('| $name | ${mean.toStringAsFixed(3)} | ${worst.toStringAsFixed(2)} ($worstLevel) |');
    }
  }

  final sections = <String, List<FrameStats>>{};
  final byType = <String, List<FrameStats>>{};
  for (final r in results) {
    for (final e in r.sections.entries) {
      (sections[e.key] ??= []).add(_Tagged(e.value, r.id));
    }
    for (final e in r.byType.entries) {
      (byType[e.key] ??= []).add(_Tagged(e.value, r.id));
    }
  }
  table('Game logic sections (inside update)', sections);
  table('Render (recording) by component type, every ${_breakdownEvery}th frame', byType);

  final f = File('build/perf_report.md')..createSync(recursive: true);
  f.writeAsStringSync(b.toString());
  print('wrote ${f.path}');
}

class _Tagged extends _Snapshot {
  _Tagged(super.s, this.level);
  final String level;
}
