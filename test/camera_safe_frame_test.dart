// ignore_for_file: invalid_use_of_internal_member
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  /// Puts the ship at ([fx], [fy]) of the world (fractions; no physics
  /// step), lets the camera settle and returns whether the ship's screen
  /// point is clear of every control zone.
  bool shipClearAt(double fx, double fy) {
    final game = h.game;
    final world = game.currentLevel!.worldSize;
    final ship = game.ship!;
    ship.body.setTransform(Vector2(world.x * fx, world.y * fy), 0);
    for (var i = 0; i < 120; i++) {
      game.debugCameraStep(kStepDt);
    }
    final p = game.camera.localToGlobal(ship.body.position);
    final zones = game.debugHudControls!.controlZones;
    expect(zones, isNotEmpty);
    return zones.every((z) => p.x < z.l || p.x > z.r || p.y < z.t || p.y > z.b);
  }

  for (final leftHanded in [false, true]) {
    final hand = leftHanded ? 'left-handed' : 'right-handed';
    for (final id in ['mine_01', 'tut_05']) {
      test('$id ($hand): ship near the floor corners stays clear of the controls',
          () async {
        await h.loadLevel(levelIndexOf(id));
        h.game.debugHudControls!.leftHanded = leftHanded;
        // Bottom-left and bottom-right corners, just inside the world.
        expect(shipClearAt(0.03, 0.97), isTrue, reason: 'bottom-left');
        expect(shipClearAt(0.97, 0.97), isTrue, reason: 'bottom-right');
        // Mid-screen at the floor: never pushed off the world by more than
        // the overscroll.
        expect(shipClearAt(0.5, 0.97), isTrue, reason: 'bottom-middle');
        final c = h.game.camera.viewfinder.position;
        final world = h.game.currentLevel!.worldSize;
        final halfH = h.game.camera.viewport.size.y / h.game.camera.viewfinder.zoom / 2;
        expect(c.y + halfH, lessThanOrEqualTo(world.y + kCameraOverscroll + 1e-6));
      });
    }
  }
}
