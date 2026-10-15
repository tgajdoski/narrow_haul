// The first flight names the camera mode on the radio (once ever),
// not again on the next level, and never on the onboarding levels.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(() => h.boot());

  Future<void> wait(double seconds) => h.step((seconds * 60).round());

  test('Look-ahead is the default camera', () {
    expect(FlightTuning.camera, CameraMode.lookAhead);
  });

  test('TOWER names the camera on the first flight of a session only', () async {
    // tut_01 teaches the controls: no camera tip there.
    await h.loadLevel(0);
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('camera'), isFalse);

    await h.loadLevel(levelIndexOf('alien_01'));
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('camera'), isTrue);

    await h.loadLevel(levelIndexOf('alien_02'));
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('camera'), isFalse);
  });
}
