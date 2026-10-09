import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/ship_fx.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  group('HullLighting', () {
    test('the light stays fixed in the world whatever the ship angle', () {
      final w = HullLighting.key;
      for (var a = -3.0; a <= 3.0; a += 0.5) {
        final l = HullLighting.toLocal(w, a);
        // Back to world: rotate by +a.
        final c = math.cos(a), s = math.sin(a);
        expect(l.x * c - l.y * s, closeTo(w.x, 1e-6));
        expect(l.x * s + l.y * c, closeTo(w.y, 1e-6));
        expect(l.z, closeTo(w.z, 1e-6));
      }
    });

    test('bucket picking wraps and blends toward the next bucket', () {
      expect(HullLighting.bucketsFor(0), (0, 1, 0.0));
      final step = 2 * math.pi / HullLighting.buckets;
      final (a0, a1, t) = HullLighting.bucketsFor(step * 2.25);
      expect((a0, a1), (2, 3));
      expect(t, closeTo(0.25, 1e-9));
      final (b0, b1, _) = HullLighting.bucketsFor(-step * 0.5);
      expect((b0, b1), (HullLighting.buckets - 1, 0));
      final (c0, _, _) = HullLighting.bucketsFor(2 * math.pi * 3 + step);
      expect(c0, 1);
    });
  });

  // The real sprites, lit in every angle bucket: the overlay may shade a
  // hull but never black it out (the "covered in black" Mule).
  group('light atlas on every ship', () {
    final sprites = {for (final s in kShips.values) s.sprite};
    for (final path in sprites) {
      test(path, () async {
        final (rgba, w, h) = await _loadRgba('assets/$path');
        // A white rim isolates the shadow for the per-pixel floor; the
        // theme-coloured one (lava orange) is checked on average.
        final white = bakeHullLightAtlas(rgba, w, h, 0xFFFFFFFF);
        final atlas = bakeHullLightAtlas(rgba, w, h, 0xFFFF5A1F);
        final aw = w * 4;
        double lum(double r, double g, double b) => 0.3 * r + 0.59 * g + 0.11 * b;
        final means = <double>[];
        for (var b = 0; b < HullLighting.buckets; b++) {
          final cell = HullLighting.cell(b, w, h);
          var artSum = 0.0, litSum = 0.0;
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              final i = (y * w + x) * 4;
              final o = ((cell.top.toInt() + y) * aw + cell.left.toInt() + x) * 4;
              if (rgba[i + 3] == 0) {
                expect(atlas[o + 3], 0, reason: 'nothing drawn off the hull');
                continue;
              }
              if (rgba[i + 3] < 255) continue;
              final art = lum(rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
              double litWith(Uint8List at) =>
                  lum(at[o] / 255, at[o + 1] / 255, at[o + 2] / 255) + art * (1 - at[o + 3] / 255);
              expect(litWith(white), greaterThanOrEqualTo(art * (1 - HullLighting.maxDark) - 0.01),
                  reason: '$path bucket $b ($x,$y)');
              final lit = litWith(atlas);
              artSum += art;
              litSum += lit;
            }
          }
          expect(litSum / artSum, greaterThan(0.85), reason: '$path bucket $b');
          means.add(litSum / artSum);
        }
        expect(means.reduce(math.max) - means.reduce(math.min), greaterThan(0),
            reason: 'the light turns with the angle');
        final c0 = HullLighting.cell(0, w, h), c8 = HullLighting.cell(8, w, h);
        var differ = 0;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final o0 = ((c0.top.toInt() + y) * aw + c0.left.toInt() + x) * 4 + 3;
            final o8 = ((c8.top.toInt() + y) * aw + c8.left.toInt() + x) * 4 + 3;
            if ((atlas[o0] - atlas[o8]).abs() > 20) differ++;
          }
        }
        expect(differ, greaterThan(200), reason: 'upright vs upside down lit differently');
      });
    }
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

  test('normals face the viewer inside and outward at the edges', () {
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
    final n = hullNormals(rgba, w, h, domePx: 12);
    (double, double, double) at(int x, int y) {
      final i = (y * w + x) * 3;
      return (n[i], n[i + 1], n[i + 2]);
    }

    final (_, _, cz) = at(32, 32);
    expect(cz, greaterThan(0.95));
    final (rx, _, _) = at(58, 32); // near the right edge
    expect(rx, greaterThan(0.3));
    final (_, ty, _) = at(32, 6); // near the top edge (y down)
    expect(ty, lessThan(-0.3));
  });

  test('flat dark paint is not a groove, a thin dark line is', () {
    // A big square: left half mid grey, right half dark grey, and one dark
    // 1 px line across the left half.
    const w = 96, h = 96;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final v = x == 30 && y > 10 && y < 86 ? 20 : (x < 48 ? 180 : 70);
        rgba
          ..[i] = v
          ..[i + 1] = v
          ..[i + 2] = v
          ..[i + 3] = 255;
      }
    }
    final n = hullNormals(rgba, w, h, domeHeight: 0, bevelHeight: 0);
    double tiltAt(int x, int y) => n[(y * w + x) * 3].abs();
    expect(tiltAt(29, 48), greaterThan(0.1), reason: 'line edge tilts');
    expect(tiltAt(70, 48), lessThan(0.01), reason: 'flat dark paint stays flat');
  });
}

Future<(Uint8List, int, int)> _loadRgba(String path) async {
  late (Uint8List, int, int) out;
  await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    out = (data!.buffer.asUint8List(), img.width, img.height);
  });
  return out;
}
