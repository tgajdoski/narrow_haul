// Two-finger pinch zoom: the pure tracker, and the camera following it.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/camera/pinch_zoom.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  group('PinchZoom', () {
    test('spreading two fingers zooms in, pinching zooms out', () {
      final p = PinchZoom();
      expect(p.down(1, const Offset(100, 100), zoom: 1), isFalse);
      expect(p.down(2, const Offset(200, 100), zoom: 1), isTrue);
      expect(p.active, isTrue);
      expect(p.move(2, const Offset(250, 100)), closeTo(1.5, 1e-9));
      expect(p.move(2, const Offset(160, 100)), closeTo(0.6, 1e-9));
      expect(p.up(2), isTrue, reason: 'a pinch that zoomed ended');
      expect(p.active, isFalse);
    });

    test('a twitch under the slop does nothing', () {
      final p = PinchZoom()
        ..down(1, const Offset(100, 100), zoom: 1)
        ..down(2, const Offset(200, 100), zoom: 1);
      expect(p.move(2, const Offset(205, 100)), isNull);
      expect(p.up(1), isFalse);
    });

    test('a finger on THRUST / FIRE never makes a pinch', () {
      final p = PinchZoom()
        ..down(1, const Offset(100, 100), zoom: 1)
        ..down(2, const Offset(700, 300), zoom: 1, blocked: true);
      expect(p.active, isFalse);
      expect(p.move(1, const Offset(50, 100)), isNull);
    });

    test('zoom stays in range', () {
      final p = PinchZoom()
        ..down(1, const Offset(0, 0), zoom: 1.5)
        ..down(2, const Offset(100, 0), zoom: 1.5);
      expect(p.move(2, const Offset(400, 0)), FlightTuning.maxZoom);
      expect(PinchZoom.step(FlightTuning.minZoom, -3), FlightTuning.minZoom);
      expect(PinchZoom.step(1, 1), closeTo(1.1, 1e-9));
    });
  });

  group('in the game', () {
    final h = GameHarness();
    setUpAll(h.boot);
    tearDown(() => FlightTuning.cameraZoom = 1);

    test('a pinch zooms the flight camera and does not steer', () async {
      final g = h.game;
      await h.loadLevel(levelIndexOf('alien_01'));
      await h.step(6 * 60); // past the close-up
      final before = g.camera.viewfinder.zoom;
      g
        ..zoomPointerDown(1, const Offset(300, 150))
        ..zoomPointerDown(2, const Offset(400, 150))
        ..zoomPointerMove(2, const Offset(450, 150));
      expect(FlightTuning.cameraZoom, closeTo(1.5, 1e-9));
      await h.step(2);
      expect(g.camera.viewfinder.zoom, greaterThan(before * 1.3));
      expect(g.rotateAxis, 0);
      g
        ..zoomPointerUp(1)
        ..zoomPointerUp(2);
      expect(g.runState, RunState.playing);
    });

    test('mouse wheel / keys step the zoom', () async {
      final g = h.game;
      await h.loadLevel(levelIndexOf('alien_01'));
      await h.step(1);
      g.zoomBy(-1);
      expect(FlightTuning.cameraZoom, closeTo(1 / 1.1, 1e-9));
      g.resetZoom();
      expect(FlightTuning.cameraZoom, 1);
    });
  });
}
