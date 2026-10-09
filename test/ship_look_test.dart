import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/ship_fx.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  group('HullLighting', () {
    test('the light stays fixed in the world whatever the ship angle', () {
      final w = HullLighting.key;
      for (var a = -3.0; a <= 3.0; a += 0.5) {
        final l = HullLighting.toLocal(w, a, 0);
        // Back to world: rotate by +a.
        final c = math.cos(a), s = math.sin(a);
        expect(l.x * c - l.y * s, closeTo(w.x, 1e-6));
        expect(l.x * s + l.y * c, closeTo(w.y, 1e-6));
        expect(l.z, closeTo(w.z, 1e-6));
      }
    });

    test('a right bank turns the top of the hull toward the right', () {
      // Light from the right: a hull rolled right faces it more.
      final right = Vector3(1, 0, 0);
      expect(HullLighting.toLocal(right, 0, 1).z, greaterThan(0));
      expect(HullLighting.toLocal(right, 0, -1).z, lessThan(0));
    });

    test('the colour matrix computes clamp(k·(n·d) + b) on an encoded normal', () {
      final m = normalLightMatrix(0, 0, 1, k: 0.5, b: 0.6);
      // Flat normal (0,0,1) encodes as (0.5, 0.5, 1).
      final v = m[0] * 0.5 + m[1] * 0.5 + m[2] * 1 + m[4] / 255;
      expect(v, closeTo(0.5 * 1 + 0.6, 1e-9));
      expect(m.sublist(15), [0, 0, 0, 1, 0]);
    });
  });

  group('ShipLook', () {
    test('bank eases toward the turn and stays within ±1', () {
      final look = ShipLook();
      for (var i = 0; i < 60; i++) {
        look.update(1 / 60, angularVelocity: 10, turnRate: 1.5, thrusting: false);
      }
      expect(look.bank, closeTo(1, 0.01));
      expect(look.bank, lessThanOrEqualTo(1));
      for (var i = 0; i < 60; i++) {
        look.update(1 / 60, angularVelocity: 0, turnRate: 1.5, thrusting: false);
      }
      expect(look.bank.abs(), lessThan(0.01));
    });

    test('the engine comes on fast and fades out softer', () {
      final look = ShipLook();
      for (var i = 0; i < 6; i++) {
        look.update(1 / 60, angularVelocity: 0, turnRate: 1.5, thrusting: true);
      }
      expect(look.thrust, greaterThan(0.9));
      expect(look.kick, greaterThan(0));
      for (var i = 0; i < 6; i++) {
        look.update(1 / 60, angularVelocity: 0, turnRate: 1.5, thrusting: false);
      }
      expect(look.thrust, inInclusiveRange(0.2, 0.7));
      expect(look.heat, greaterThan(0), reason: 'the nozzle stays warm a while');
    });

    test('RCS puffs fire when a turn starts, not during a steady turn', () {
      final look = ShipLook();
      var start = 0;
      for (var i = 0; i < 12; i++) {
        start += look.update(1 / 60, angularVelocity: 1.5, turnRate: 1.5, thrusting: false);
      }
      expect(start, greaterThan(0));
      expect(look.angAccel, greaterThan(0));
      for (var i = 0; i < 60; i++) {
        look.update(1 / 60, angularVelocity: 1.5, turnRate: 1.5, thrusting: false);
      }
      var steady = 0;
      for (var i = 0; i < 30; i++) {
        steady += look.update(1 / 60, angularVelocity: 1.5, turnRate: 1.5, thrusting: false);
      }
      expect(steady, 0);
    });
  });

  test('nav lights and thrusters sit on every hull', () {
    for (final spec in kShips.values) {
      final pts = HullPoints.of(spec);
      final r = shipSpriteRect(spec);
      for (final p in [pts.wingTip, pts.noseSide, pts.spine]) {
        expect(r.contains(p), isTrue, reason: '${spec.id} $p');
      }
      expect(pts.wingTip.dx, greaterThan(0.2), reason: spec.id);
      expect(pts.noseSide.dy, lessThan(pts.wingTip.dy + 0.5), reason: spec.id);
    }
  });

  test('baked normals face the viewer inside and outward at the edges', () {
    // A 64×64 opaque disc.
    const w = 64, h = 64;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final inside = math.pow(x - 32, 2) + math.pow(y - 32, 2) < 28 * 28;
        rgba
          ..[i] = 200
          ..[i + 1] = 200
          ..[i + 2] = 200
          ..[i + 3] = inside ? 255 : 0;
      }
    }
    final n = bakeHullNormals(rgba, w, h, domePx: 12);
    (double, double, double) at(int x, int y) {
      final i = (y * w + x) * 4;
      return (n[i] / 255 * 2 - 1, n[i + 1] / 255 * 2 - 1, n[i + 2] / 255 * 2 - 1);
    }

    final (_, _, cz) = at(32, 32);
    expect(cz, greaterThan(0.95));
    final (rx, _, _) = at(58, 32); // near the right edge
    expect(rx, greaterThan(0.3));
    final (_, ty, _) = at(32, 6); // near the top edge (y down)
    expect(ty, lessThan(-0.3));
    expect(n[3], 0, reason: 'outside stays transparent');
  });
}
