// Visual smoke run on a real device/desktop: drives menus and flights and
// saves screenshots of the rendered frames for eyeballing.
//   flutter test integration_test/visual_smoke_test.dart -d macos
// Screenshots go to the app's temp dir (path printed as SHOTS_DIR=...).
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import 'capture_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('visual smoke tour', (tester) async {
    // Never touch the real save.
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('nh_shots_');
    // ignore: avoid_print
    print('SHOTS_DIR=${dir.path}');

    final cap = Capture(tester, dir);
    final wait = cap.wait;
    Future<void> shot(String name) => cap.shot(name);

    app.main();
    // Fresh prefs: the first-launch "Delivered by" credits play over the menu.
    await wait(2.2);
    await shot('00_credits');
    await wait(2.5);
    final game = tester.widget<GameWidget<NarrowHaulGame>>(
      find.byType(GameWidget<NarrowHaulGame>),
    ).game!;
    await shot('01_menu');

    game.overlays
      ..remove('menu')
      ..add('levelSelect');
    await wait(1.2);
    await shot('02_level_select');

    // Tutorial 1: intro card + onboarding hint + HUD.
    game.startLevel(0);
    await wait(1.0);
    await shot('03_tut1_intro');
    // Ship waits on its pad until the first input: no crash while reading.
    await wait(2.5);
    await shot('04_tut1_waiting_on_pad');

    game.pauseGame();
    await wait(0.4);
    await shot('05_pause');
    game.overlays
      ..remove('pause')
      ..add('settings');
    await wait(0.4);
    await shot('06_settings');
    game.resumeGame();
    await wait(0.3);

    // Short hop (long enough to count as "used thrust"), shot mid-air.
    game.thrustHeld = true;
    await wait(0.5);
    game.thrustHeld = false;
    await wait(0.6);
    await shot('04b_tut1_hint_after_thrust');

    int indexOf(String id) =>
        LevelRegistry.flat.indexWhere((d) => d.saveId.contains(id));

    for (final id in ['ice_03', 'lava_03', 'alien_05', 'mine_03']) {
      game.startLevel(indexOf(id));
      await wait(2.8);
      await shot('07_$id');
    }

    // Crash: burn straight up into the ceiling.
    game.startLevel(indexOf('lava_03'));
    await wait(2.6);
    game.thrustHeld = true;
    final crashDeadline = DateTime.now().add(const Duration(seconds: 12));
    while (game.runState == RunState.playing && DateTime.now().isBefore(crashDeadline)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.thrustHeld = false;
    await wait(0.15);
    await shot('08_crash_explosion');
    await wait(1.2);
    await shot('09_game_over');

    // Level complete screen (forced: a real delivery can't be scripted).
    game.restartLevel();
    await wait(0.5);
    game
      ..lastLevelStars = 2
      ..lastLevelTimeSeconds = 48.3
      ..lastLevelFuelFraction = 0.52;
    game.overlays.add('levelComplete');
    await wait(1.6);
    await shot('10_level_complete');

    await AudioService.dispose();
  });
}
