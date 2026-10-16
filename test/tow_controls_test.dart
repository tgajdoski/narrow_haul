// The pilot's tow controls: the TOW pad's place on every phone, and in the
// real game a drop that doesn't snap straight back, a re-hook after pulling
// clear, and a winch that stays inside its limits.
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  group('TOW pad layout', () {
    const screens = [Size(568, 320), Size(667, 375), Size(844, 390), Size(1194, 834)];
    const notch = EdgeInsets.only(left: 47, right: 47, bottom: 21);
    const tr = HudButtonLayout.towRadius;

    for (final screen in screens) {
      for (final insets in [EdgeInsets.zero, notch]) {
        for (final left in [false, true]) {
          test('${screen.width.toInt()}×${screen.height.toInt()} '
              '${insets == EdgeInsets.zero ? 'flat' : 'notch'} '
              '${left ? 'left' : 'right'}-handed', () {
            final l = HudButtonLayout(screen, insets: insets, leftHanded: left);
            for (var n = 0; n <= 6; n++) {
              final t = l.towCenter(railSlots: n);
              final why = 'rail of $n';
              // On screen, inside the safe area.
              expect(t.dx - tr, greaterThanOrEqualTo(insets.left), reason: why);
              expect(t.dx + tr, lessThanOrEqualTo(screen.width - insets.right), reason: why);
              expect(t.dy - tr, greaterThanOrEqualTo(insets.top + HudButtonLayout.topClear - 30), reason: why);
              // Clear of THRUST, FIRE, every rail slot and the dial at rest.
              expect((t - l.thrust).distance, greaterThan(HudButtonLayout.thrustRadius + tr), reason: why);
              expect((t - l.fire).distance, greaterThan(HudButtonLayout.fireRadius + tr), reason: why);
              for (final c in n > 1 ? l.railCenters(n) : const <Offset>[]) {
                expect((t - c).distance, greaterThan(HudButtonLayout.slotRadius + tr), reason: why);
              }
              expect((t - l.dialRest).distance, greaterThan(HudButtonLayout.dialRadius + tr), reason: why);
              // The radio band left between the dial and the controls.
              expect(l.towReach(railSlots: n), greaterThan((t.dx - l.thrust.dx).abs() + tr));
            }
          });
        }
      }
    }
  });

  group('drop, re-hook and winch in the real game', () {
    final h = GameHarness();
    setUpAll(h.boot);

    /// tut_01's pod hooked by a kinematic ship hovering over it.
    Future<void> hookUp() async {
      await h.loadLevel(levelIndexOf('tut_01'), skipHazards: true);
      final g = h.game;
      final ship = g.ship!;
      ship.body
        ..setType(BodyType.kinematic)
        ..angularVelocity = 0
        ..linearVelocity = Vector2.zero();
      final pod = g.cargo!.body.worldCenter;
      ship.body.setTransform(pod - Vector2(0, 1.2 + ship.rearLocalY), 0);
      for (var i = 0; i < 120 && !(g.cargoAttachment?.attached ?? false); i++) {
        await h.step(1);
      }
      expect(g.cargoAttachment!.attached, isTrue);
      await h.step(1);
    }

    Future<void> moveShip(Vector2 v, double seconds) async {
      final body = h.game.ship!.body;
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        body
          ..linearVelocity = v
          ..angularVelocity = 0;
        await h.step(1);
      }
      body.linearVelocity = Vector2.zero();
    }

    test('a drop lets go and does not hook again until pulled clear', () async {
      await hookUp();
      final g = h.game;
      expect(g.cargoAttachment!.canRelease, isTrue);
      g.releaseTow();
      expect(g.cargoAttachment!.attached, isFalse);
      // Hovering right over it: no snap back.
      await h.step(60);
      expect(g.cargoAttachment!.attached, isFalse);
      // Up and away, then back down over the pod: it hooks again.
      await moveShip(Vector2(0, -2), 1.5);
      final pod = g.cargo!.body.worldCenter;
      g.ship!.body.setTransform(pod - Vector2(0, 1.2 + g.ship!.rearLocalY), 0);
      for (var i = 0; i < 120 && !g.cargoAttachment!.attached; i++) {
        await h.step(1);
      }
      expect(g.cargoAttachment!.attached, isTrue, reason: 'hooks again after pulling clear');
    });

    test('the winch pays out to its limit and reels in to the shortest tow', () async {
      await hookUp();
      final g = h.game;
      final a = g.cargoAttachment!;
      final coupling = a.children.whereType<RopePhysicsCoupling>().single;
      for (var i = 0; i < 60 * 8; i++) {
        a.winch(1, 1 / 60);
      }
      expect(a.lineLength, closeTo(coupling.maxPilotLength, 1e-6));
      await h.step(60);
      expect(a.lineLength, closeTo(coupling.maxPilotLength, 1e-6), reason: 'the auto winch keeps a pay out');
      for (var i = 0; i < 60 * 8; i++) {
        a.winch(-1, 1 / 60);
      }
      expect(a.lineLength, closeTo(a.rope.minTowLength, 1e-6));
    });

    test('no drop or winch in a demo or before a pod is hooked', () async {
      await h.loadLevel(levelIndexOf('tut_01'), skipHazards: true);
      final g = h.game;
      expect(g.cargoAttachment!.canRelease, isFalse);
      g.releaseTow(); // nothing to drop: no throw
      g.cargoAttachment!.winch(1, 1);
      expect(g.cargoAttachment!.lineLength, isNull);
    });
  });
}
