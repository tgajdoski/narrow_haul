// Store video frames: plays the store storyboard (hangar, story chapter,
// briefing, real demo flights, a story radio beat, results, Garage) and saves
// every frame with its game time, for tool/store/make_store_video.sh to cut.
//   flutter test integration_test/store_video_test.dart -d macos \\
//     --dart-define=STORE_CAPTURE=true --dart-define=STORE_VIDEO_TARGET=iphone
//
// Saving a frame takes longer than a frame, so the capture runs in slow
// motion: `timeDilation` slows every Flutter ticker, Flame's game loop
// included, and each frame is stamped with game time (wall time ÷ dilation).
// The assembler turns the stamps into a constant 30 fps stream.
//
// One target per run (the second target of a run has hung before). Frames go
// to the app's temp dir, printed as VIDEO_DIR=. Uses mocked prefs with a
// played-in save, never the real one.
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:narrow_haul/game/components/route_guide.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/overlay_ids.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import 'capture_helpers.dart';

class _Target {
  const _Target(this.logical, this.pixelWidth);

  final Size logical;
  final int pixelWidth;
}

const _targets = {
  // App Store iPhone App Preview, 1920×886.
  'iphone': _Target(Size(932, 430), 1920),
  // App Store 13" iPad App Preview, 1600×1200.
  'ipad': _Target(Size(1366, 1024), 1600),
  // YouTube / Google Play promo, 1920×1080.
  'youtube': _Target(Size(960, 540), 1920),
  // App Store product page header (21:9) and search results (3:2) videos:
  // 16:9 4K flights with no HUD, cropped by assemble_store_video.py.
  'header': _Target(Size(1280, 720), 3840),
};

const _target = String.fromEnvironment('STORE_VIDEO_TARGET', defaultValue: 'iphone');

/// Flights without the HUD (the header / search art videos).
const _clean = _target == 'header';

/// Slow-motion factor while frames are saved (game seconds per wall second
/// is 1 / this).
final _dilation = double.parse(const String.fromEnvironment('STORE_VIDEO_DILATION', defaultValue: '8'));

/// Comma-separated scene names to record (default: all).
const _onlyScenes = String.fromEnvironment('STORE_VIDEO_SCENES');

/// Demo flights: (scene, level, demo seconds to start at, seconds to record).
/// Windows are picked from each route's hook / landing times.
const _flights = <(String, String, double, double)>[
  ('alien', 'alien_05', 11.0, 9),
  ('mine', 'mine_03', 12.5, 9),
  ('orbit', 'orbit_02', 15.0, 9),
  ('ice', 'ice_03', 19.0, 8),
  ('lava', 'lava_03', 15.0, 9),
  ('redoubt', 'redoubt_02', 15.5, 10),
  ('expedition', 'exp_00', 18.0, 9),
];

const _demoLevels = ['alien_05', 'mine_03', 'orbit_02', 'ice_03', 'lava_03', 'redoubt_02', 'exp_00'];

/// Played-in save (as the store screenshots): early worlds starred,
/// mid-career rank, some coins, demo routes unlocked, story chapters unread.
Map<String, Object> _seededPrefs() {
  final prefs = <String, Object>{
    'save_v2': true,
    'save_v3': true,
    'credits_seen': true,
    'xp_total': 6800,
    'cosmetic_currency': 1240,
    'sound_enabled': false,
    'music_enabled': false,
    'haptics_enabled': false,
    for (final id in _demoLevels) 'route_unlocked_$id': true,
  };
  final flat = LevelRegistry.flat;
  final starred = (flat.length * 0.7).floor();
  for (int i = 0; i < starred; i++) {
    prefs['stars2_${flat[i].saveId}'] = i % 4 == 3 ? 2 : 3;
  }
  return prefs;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store video frames', (tester) async {
    final target = _targets[_target]!;
    SharedPreferences.setMockInitialValues(_seededPrefs());
    final root = await Directory.systemTemp.createTemp('nh_video_');
    final out = Directory('${root.path}/$_target')..createSync(recursive: true);
    // ignore: avoid_print
    print('VIDEO_DIR=${out.path}');

    await binding.setSurfaceSize(target.logical);
    app.main();
    final idle = Capture(tester, out);
    // Pump until the game is mounted (the intro plays meanwhile).
    for (var i = 0; i < 200 && find.byType(GameWidget<NarrowHaulGame>).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final game = tester.widget<GameWidget<NarrowHaulGame>>(
      find.byType(GameWidget<NarrowHaulGame>),
    ).game!;

    // The app pauses a flight when its window loses focus (lifecycle
    // inactive); the capture keeps it going.
    void keepRunning() {
      if (game.isPaused) game.resumeGame();
    }

    /// [idle.wait] that keeps a flight running.
    Future<void> play(double seconds) async {
      for (var t = 0.0; t < seconds; t += 0.25) {
        keepRunning();
        await idle.wait(0.25);
      }
      keepRunning();
    }

    bool wanted(String scene) => _onlyScenes.isEmpty || _onlyScenes.split(',').contains(scene);

    /// Saves frames for [seconds] of game time into `<scene>/`, with a
    /// `times.txt` of each frame's game time.
    Future<void> record(String scene, double seconds) async {
      final dir = Directory('${out.path}/$scene')..createSync(recursive: true);
      final cap = Capture(tester, dir);
      final times = StringBuffer();
      timeDilation = _dilation;
      final clock = Stopwatch()..start();
      var n = 0;
      double gameT() => clock.elapsedMicroseconds / 1e6 / _dilation;
      while (gameT() < seconds) {
        keepRunning();
        final t = gameT();
        await cap.shot('f_${n.toString().padLeft(5, '0')}', outputWidth: target.pixelWidth);
        times.writeln(t.toStringAsFixed(4));
        n++;
      }
      timeDilation = 1;
      File('${dir.path}/times.txt').writeAsStringSync(times.toString());
      // ignore: avoid_print
      print('SCENE $scene frames=$n game=${seconds}s fps=${(n / seconds).toStringAsFixed(1)}');
    }

    /// A button by its label, whatever its case.
    Finder label(String text) => find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').toLowerCase() == text.toLowerCase(),
        );

    int indexOf(String id) => LevelRegistry.flat.indexWhere((d) => d.saveId == id);

    // 1. The launch intro, while the game finishes loading.
    if (wanted('intro') && game.introVisible.value) {
      await record('intro', 2.0);
    }
    await idle.wait(3);
    game.introVisible.value = false;
    await idle.wait(1);

    // 2. The hangar.
    if (wanted('hangar')) {
      game.backToMenu();
      await idle.wait(1.5);
      await record('hangar', 4);
    }

    // 3. The missions star map.
    if (wanted('missions')) {
      game.overlays
        ..remove(OverlayIds.menu)
        ..add(OverlayIds.levelSelect);
      await idle.wait(1.2);
      await record('missions', 4);
    }

    // 4. Story: the Xenar Caverns chapter card, then the mission briefing.
    if (wanted('chapter')) {
      if (!game.overlays.isActive(OverlayIds.levelSelect)) {
        game.overlays
          ..remove(OverlayIds.menu)
          ..add(OverlayIds.levelSelect);
      }
      final alien = LevelRegistry.worlds.firstWhere((w) => w.id == 'alien');
      game.openBriefing(indexOf(alien.levels.first.saveId));
      await idle.wait(1.0);
      await record('chapter', 5);
      final next = label('Next');
      if (next.evaluate().isNotEmpty) {
        await tester.tap(next.first, warnIfMissed: false);
        await idle.wait(0.6);
        await record('chapter2', 4);
      }
      // Through to the briefing.
      for (var i = 0; i < 6; i++) {
        final done = label('Briefing');
        if (done.evaluate().isNotEmpty) {
          await tester.tap(done.first, warnIfMissed: false);
          break;
        }
        final more = label('Next');
        if (more.evaluate().isEmpty) break;
        await tester.tap(more.first, warnIfMissed: false);
        await idle.wait(0.4);
      }
      await idle.wait(1.2);
      await record('briefing', 5);
      game.closeBriefing();
      game.overlays.remove(OverlayIds.levelSelect);
    }

    // 5. A first flight's start: the level card, countdown and a radio
    // story beat (story beats play on a first attempt, never in a demo).
    if (wanted('radio')) {
      game.startLevel(indexOf('orbit_02'));
      await idle.wait(0.3);
      await record('radio', 9);
    }

    // 6. Real demo flights (the bundled bot recordings).
    for (final (scene, id, from, seconds) in _flights) {
      if (!wanted(scene)) continue;
      game.startLevel(indexOf(id));
      await play(1.5);
      await game.startDemoFlight();
      game.overlays.remove(OverlayIds.demo);
      // A clean flight: no dotted demo route.
      for (final c in game.world.children.whereType<RouteGuideLine>().toList()) {
        c.removeFromParent();
      }
      // Run the replay up to the window at normal speed.
      await play(from);
      game.overlays.remove(OverlayIds.demo);
      for (final c in game.world.children.whereType<RouteGuideLine>().toList()) {
        c.removeFromParent();
      }
      if (_clean) game.debugHideHud(true);
      await record(scene, seconds);
      if (_clean) game.debugHideHud(false);
    }

    // 7. The result screen (forced, like the store screenshots).
    if (wanted('complete')) {
      game.startLevel(indexOf('alien_05'));
      await idle.wait(1.5);
      game
        ..lastLevelStars = 3
        ..lastLevelTimeSeconds = 41.7
        ..lastLevelFuelFraction = 0.64;
      game.overlays.add(OverlayIds.levelComplete);
      await idle.wait(0.2);
      await record('complete', 5);
      game.overlays.remove(OverlayIds.levelComplete);
    }

    // 8. The Garage: liveries on the spinning ship showcase.
    if (wanted('garage')) {
      game.backToMenu();
      await idle.wait(0.8);
      game.garageTab = CosmeticsService.catShip;
      game.overlays
        ..remove(OverlayIds.menu)
        ..add(OverlayIds.cosmetics);
      await idle.wait(1.2);
      await record('garage', 5);
      game.overlays.remove(OverlayIds.cosmetics);
    }

    timeDilation = 1;
    await binding.setSurfaceSize(null);
    await AudioService.dispose();
  }, timeout: const Timeout(Duration(minutes: 60)));
}
