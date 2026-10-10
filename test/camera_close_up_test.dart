// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);
  tearDown(() => FlightTuning.camera = CameraMode.dynamicZoom);

  void camera(double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += kStepDt) {
      h.game.debugCameraStep(kStepDt);
    }
  }

  test('a level opens close on the ship and is back to the flight view by GO', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    expect(h.game.debugCloseUp, greaterThan(2), reason: 'close-up on load');
    camera(0.9); // the level card
    expect(h.game.debugCloseUp, greaterThan(2));
    camera(3.2); // 3 · 2 · 1 · GO
    expect(h.game.debugCloseUp, 1);
  });

  test('the first input releases the close-up at once', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    camera(0.3);
    h.game.ship!.launch();
    camera(0.5);
    expect(h.game.debugCloseUp, 1);
  });

  test('Centred camera keeps its one zoom: no close-up', () async {
    FlightTuning.camera = CameraMode.centered;
    await h.loadLevel(levelIndexOf('mine_01'));
    expect(h.game.debugCloseUp, 1);
  });

  test('a delivery pushes in on the pad', () async {
    await h.loadLevel(levelIndexOf('mine_01'));
    h.game.ship!.launch();
    camera(1);
    await h.game.debugDeliver();
    expect(h.game.runState, RunState.won);
    for (var i = 0; i < 30; i++) {
      h.game.update(kStepDt);
    }
    expect(h.game.debugCloseUp, greaterThan(1.1));
  });
}
