import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';

/// Every cargo sprite: the shared one plus each world's own.
List<File> _cargoSprites() => [
      File('assets/cargo.png'),
      for (final w in LevelRegistry.worlds)
        for (final name in const ['cargo.png', 'cargo_heavy.png'])
          File('assets/themes/${w.themeId}/$name'),
    ].where((f) => f.existsSync()).toList();

/// Larger side of the solid part (alpha >= 128) as a fraction of the width,
/// and its centre offset from the image centre (fraction of the width).
Future<(int, int, double, double)> _framing(File f) async {
  final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
  final img = (await codec.getNextFrame()).image;
  final w = img.width, h = img.height;
  final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba.getUint8((y * w + x) * 4 + 3) < 128) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  final side = (x1 - x0 + 1) > (y1 - y0 + 1) ? x1 - x0 + 1 : y1 - y0 + 1;
  final dx = (x0 + x1 + 1) / 2 - w / 2, dy = (y0 + y1 + 1) / 2 - h / 2;
  final off = (dx.abs() > dy.abs() ? dx.abs() : dy.abs()) / w;
  return (w, h, side / w, off);
}

void main() {
  testWidgets('cargo sprites are square, centred, the pod filling 80%',
      (tester) async {
    await tester.runAsync(() async {
      final files = _cargoSprites();
      expect(files, isNotEmpty);
      for (final f in files) {
        final (w, h, fill, off) = await _framing(f);
        // CargoBody draws every sprite at one size (_spriteHalf), so the
        // pod's solid disc must cover the same share of each image.
        expect(w, h, reason: '${f.path} is not square');
        expect(fill, closeTo(0.8, 0.05), reason: '${f.path} pod fill');
        expect(off, lessThan(0.04), reason: '${f.path} pod off-centre');
      }
    });
  });

  test('every world has its pod, and a heavy one exactly where pods are heavy',
      () {
    for (final w in LevelRegistry.worlds) {
      final dir = 'assets/themes/${w.themeId}';
      expect(File('$dir/cargo.png').existsSync(), isTrue,
          reason: '$dir/cargo.png missing');
      final heavyLevels = w.levels.any((l) => l.modifiers.cargoDensityMul > 1.0);
      expect(File('$dir/cargo_heavy.png').existsSync(), heavyLevels,
          reason: heavyLevels
              ? '$dir has heavy-cargo levels but no cargo_heavy.png'
              : '$dir/cargo_heavy.png is never used');
    }
  });
}
