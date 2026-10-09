// On-device render benchmark: replays the bundled demo flight of a few heavy
// levels (the real visuals: terrain, fields, turrets, shells, HUD) and
// records Flutter frame timings (UI build + raster) for each.
//
//   flutter drive --profile --dart-define=PERF=true \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_flight_test.dart -d <iphone>
//
// Frame timings come from the game's own PerfMonitor (engine FrameTiming
// callbacks; no VM-service connection, so it also runs in the macOS
// sandbox). Writes build/perf_device_<level>.json (ms p50/p95/p99/max for
// UI build, raster, update and render, plus late-frame counts) and prints
// one `PERF <level> demo …` line per level.
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/perf/perf_monitor.dart';
import 'package:narrow_haul/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Big caves, force fields, moving obstacles and turret fights.
const _levels = ['tut_08', 'alien_08', 'mine_08', 'ice_07', 'lava_07', 'orbit_06', 'redoubt_04'];

/// Seconds of each demo to sample (most demos run 40–90 s).
const _seconds = 30;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo flights frame timings', (tester) async {
    expect(kPerfProbe, isTrue, reason: 'run with --dart-define=PERF=true');
    SharedPreferences.setMockInitialValues({
      'credits_seen': true,
      'sound_enabled': false,
      'music_enabled': false,
      'haptics_enabled': false,
      for (final id in _levels) 'route_unlocked_$id': true,
    });
    app.main();
    Future<void> wait(double s) => tester.pump(Duration(milliseconds: (s * 1000).round()));
    for (var i = 0; i < 40; i++) {
      await wait(0.1);
    }
    final game = tester.widget<GameWidget<NarrowHaulGame>>(find.byType(GameWidget<NarrowHaulGame>)).game!;
    game.introVisible.value = false;

    for (final id in _levels) {
      final index = LevelRegistry.flat.indexWhere((d) => d.saveId == id);
      expect(index, isNonNegative, reason: id);
      game.startLevel(index);
      await wait(1.5);
      await game.startDemoFlight();
      await wait(1.0);
      for (var t = 0.0; t < _seconds && !game.demoFinished.value; t += 0.1) {
        await wait(0.1);
      }
      (binding.reportData ??= {})[id] = PerfMonitor.toJson();
      game.backToMenu();
      await wait(1.0);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
