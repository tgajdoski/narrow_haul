// Expedition tour: plays every Expedition's demo flight (the autopilot's
// recorded 3★ run) in a real window, one after another.
//   flutter test integration_test/expedition_tour_test.dart -d macos \\
//     --dart-define=STORE_CAPTURE=true [--dart-define=EXP=exp_03,exp_07]
// Add --dart-define=PLAY=true to fly them yourself (keyboard: arrows/WASD,
// Space to thrust) instead of watching the demos; Esc → pause → menu ends one.
// Uses mocked prefs with the Full Game granted, never the real save, and
// buys nothing.
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Comma-separated saveIds to play, any mission (default: every Expedition).
const _only = String.fromEnvironment('EXP');

/// Fly the Expeditions yourself instead of watching their demos.
const _play = bool.fromEnvironment('PLAY');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  NarrowHaulGame? game;

  Future<void> wait(WidgetTester tester, double seconds) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      // Switching to another window pauses the game; keep the tour going.
      if (!_play && (game?.isPaused ?? false)) game!.resumeGame();
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('expedition tour', timeout: Timeout.none, (tester) async {
    final flat = LevelRegistry.flat;
    SharedPreferences.setMockInitialValues({
      'save_v2': true,
      'save_v3': true,
      'credits_seen': true,
      'xp_total': 6800,
      'iap_granted_nh_full_game': true,
      for (final d in flat)
        if (!(d is CaveLevelDef && d.spec.isExpedition)) 'stars2_${d.saveId}': 3,
    });
    await binding.setSurfaceSize(const Size(956, 440));
    app.main();
    await wait(tester, 4);
    final g = game = tester
        .widget<GameWidget<NarrowHaulGame>>(find.byType(GameWidget<NarrowHaulGame>))
        .game!;

    // EXP picks any missions by id, in the order given; default: every
    // Expedition.
    final tour = _only.isEmpty
        ? [
            for (var i = 0; i < flat.length; i++)
              if (flat[i] case CaveLevelDef(:final spec) when spec.isExpedition) i,
          ]
        : [for (final id in _only.split(',')) flat.indexWhere((d) => d.saveId == id)]
            .where((i) => i >= 0)
            .toList();
    for (final i in tour) {
      final id = flat[i].saveId;
      // ignore: avoid_print
      print('TOUR $id ${flat[i].name}');
      await ProgressService.instance.setRouteUnlocked(id);
      g.startLevel(i);
      await wait(tester, 3);
      if (_play) {
        // Yours until it's delivered or you leave it (back to the hangar).
        while (g.runState != RunState.won && g.runState != RunState.menu) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await wait(tester, 4);
        continue;
      }
      await g.startDemoFlight();
      final limit = DateTime.now().add(const Duration(minutes: 5));
      while (!g.demoFinished.value && DateTime.now().isBefore(limit)) {
        await wait(tester, 0.5);
      }
      await wait(tester, 2); // a moment on the last pad
    }
    // ignore: avoid_print
    print('TOUR done');
  });
}
