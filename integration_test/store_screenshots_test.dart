// Store screenshots: renders the same scenes at each store size from one run.
//   flutter test integration_test/store_screenshots_test.dart -d macos \\
//     --dart-define=STORE_CAPTURE=true --dart-define=STORE_TARGETS=ios_69,play_1080
// The iPad layout (1376×1032 pt) doesn't fit a laptop screen, so that set runs
// on the iPad Pro 13" simulator with STORE_TARGETS=ios_ipad13.
// tool/store/capture_screenshots.sh runs both.
// then `tool/store/collect_screenshots.sh` copies them from the app sandbox
// (path printed as SHOTS_DIR=...) into art_src/store/screenshots/.
//
// Each target lays the app out at the device's logical size and saves it at
// the device's pixel size, so the HUD has the same proportions as on the
// device. Uses mocked prefs with a played-in save, never the real one.
import 'dart:io';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import 'capture_helpers.dart';

class _Target {
  const _Target(this.folder, this.logical, this.pixelWidth, this.zoom);

  final String folder;
  final Size logical;
  final int pixelWidth;

  /// Camera zoom (px/m) for flight shots: closer than the in-game 28 so the
  /// ship and pod read at store-thumbnail size.
  final double zoom;
}

const _targets = [
  // App Store 6.9" (iPhone 17 Pro Max: 956×440 pt @3x).
  _Target('ios_69', Size(956, 440), 2868, 44),
  // App Store 13" iPad (iPad Pro 13": 1376×1032 pt @2x).
  _Target('ios_ipad13', Size(1376, 1032), 2752, 64),
  // Google Play phone/tablet, 16:9 (Play caps the aspect at 2:1).
  _Target('play_1080', Size(960, 540), 1920, 48),
];

/// Comma-separated target folders to render (default: all).
const _only = String.fromEnvironment('STORE_TARGETS');

/// Output folder override. The iOS simulator removes the app (and its temp
/// dir) when the test ends, but its apps can write to host paths.
const _outDir = String.fromEnvironment('STORE_OUT');

/// Flight shots: (file prefix, level, how far along the tow route, firing).
const _scenes = <(String, String, double, bool)>[
  ('01', 'alien_05', 0.45, false),
  ('02', 'mine_03', 0.4, false),
  ('03', 'ice_03', 0.5, false),
  ('04', 'lava_03', 0.4, false),
  ('05', 'orbit_02', 0.45, false),
  ('06', 'redoubt_02', 0.35, true),
  ('07', 'alien_03', 0.5, false),
];

/// Played-in save: early worlds starred, mid-career rank, some coins.
Map<String, Object> _seededPrefs() {
  final prefs = <String, Object>{
    'save_v2': true,
    'save_v3': true,
    'credits_seen': true,
    'xp_total': 6800,
    'cosmetic_currency': 1240,
    'sound_enabled': false,
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

  testWidgets('store screenshots', (tester) async {
    SharedPreferences.setMockInitialValues(_seededPrefs());
    final root = _outDir.isEmpty
        ? await Directory.systemTemp.createTemp('nh_store_')
        : (Directory(_outDir)..createSync(recursive: true));
    // ignore: avoid_print
    print('SHOTS_DIR=${root.path}');

    final targets = [
      for (final t in _targets)
        if (_only.isEmpty || _only.split(',').contains(t.folder)) t,
    ];
    await binding.setSurfaceSize(targets.first.logical);
    app.main();
    await Capture(tester, root).wait(3);
    final game = tester.widget<GameWidget<NarrowHaulGame>>(
      find.byType(GameWidget<NarrowHaulGame>),
    ).game!;

    int indexOf(String id) => LevelRegistry.flat.indexWhere((d) => d.saveId == id);

    /// Flies the level's ship mid-tunnel with the pod in tow: both are put
    /// on the validator's clear route (pickup → goal) [along] of the way,
    /// the pod ~1.1 m behind so it hooks on, then the ship hovers forward
    /// for a moment so the rope pulls taut and the plume is lit.
    Future<void> towPose(Capture cap, String id, double zoom, {double along = 0.4, bool fire = false}) async {
      final index = indexOf(id);
      game.startLevel(index);
      await cap.wait(3.0);
      final def = LevelRegistry.flat[index] as CaveLevelDef;
      final route = analyzeFlight(def.spec, ship: LevelRegistry.shipFor(index))!.towRoute;
      final i = (route.length * along).round().clamp(12, route.length - 13);
      Vector2 at(int k) => Vector2(route[k].x, route[k].y);
      final heading = at(i + 12) - at(i);
      // Nose leans into the direction of travel (y is down).
      final bank = math.atan2(heading.x, -heading.y).clamp(-0.55, 0.55);
      final s = game.ship!;
      final c = game.cargo!;
      c.body
        ..setTransform(at(i - 11), 0)
        ..linearVelocity.setZero()
        ..angularVelocity = 0;
      s.revive(position: at(i), angle: bank, fuel: s.maxFuel * 0.72);
      game.thrustHeld = true; // launches the ship (gravity on)
      game.camera.viewfinder.zoom = zoom;
      final end = DateTime.now().add(const Duration(milliseconds: 900));
      while (DateTime.now().isBefore(end) && game.runState == RunState.playing) {
        final v = s.body.linearVelocity;
        game.thrustHeld = v.y > -0.25;
        game.rotateAxis = ((bank - s.body.angle) * 3).clamp(-1.0, 1.0);
        game.fireHeld = fire;
        await tester.pump(const Duration(milliseconds: 16));
      }
      game.thrustHeld = true; // plume visible in the frame
      game.fireHeld = false;
      game.rotateAxis = 0;
    }

    for (final t in targets) {
      await binding.setSurfaceSize(t.logical);
      final dir = Directory('${root.path}/${t.folder}')..createSync(recursive: true);
      final cap = Capture(tester, dir);
      Future<void> shot(String name) => cap.shot(name, outputWidth: t.pixelWidth);

      game.backToMenu();
      await cap.wait(1.5);
      await shot('09_menu');

      game.overlays
        ..remove('menu')
        ..add('levelSelect');
      await cap.wait(1.2);
      await shot('08_missions');
      game.overlays.remove('levelSelect');

      for (final (n, id, along, fire) in _scenes) {
        await towPose(cap, id, t.zoom, along: along, fire: fire);
        await shot('${n}_$id');
        game.thrustHeld = false;
      }

      // Result screen (a real delivery can't be scripted; forced like the
      // smoke test).
      game.restartLevel();
      await cap.wait(0.5);
      game
        ..lastLevelStars = 3
        ..lastLevelTimeSeconds = 41.7
        ..lastLevelFuelFraction = 0.64;
      game.overlays.add('levelComplete');
      await cap.wait(2.5);
      await shot('10_level_complete');
      game.overlays.remove('levelComplete');

      game.backToMenu();
      await cap.wait(0.8);
      game.overlays
        ..remove('menu')
        ..add('cosmetics');
      await cap.wait(1.2);
      await shot('11_garage');
      game.overlays.remove('cosmetics');

      game.overlays.add('pilotProfile');
      await cap.wait(1.2);
      await shot('12_logbook');
      game.overlays.remove('pilotProfile');

      // IAP review screenshot: Settings with the purchase rows.
      game.overlays.add('settings');
      await cap.wait(1.0);
      await shot('13_settings_iap');
      game.overlays.remove('settings');
    }

    await binding.setSurfaceSize(null);
    await AudioService.dispose();
  });
}
