import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';

/// Optional per-world art from `assets/themes/<id>/`. Every field is null when
/// its file is missing, and each consumer falls back to the flat vector look,
/// so worlds can be skinned one file at a time.
class ThemeAssets {
  const ThemeAssets({
    this.rock,
    this.far,
    this.mid,
    this.near,
    this.decor,
    this.cargo,
    this.cargoHeavy,
  });

  /// Seamless tileable rock fill (1024×1024).
  final ui.Image? rock;

  /// Parallax layers (1920×1080, horizontally tileable; mid/near transparent).
  final ui.Image? far;
  final ui.Image? mid;
  final ui.Image? near;

  /// Edge prop sheet: 4 square cells in a row, each prop growing up from the
  /// bottom-center of its cell.
  final ui.Image? decor;

  /// Cargo pod (square, the pod's disc filling 80% of it, centred). Falls back
  /// to the shared `assets/cargo.png`.
  final ui.Image? cargo;

  /// Pod on heavy-cargo levels (`cargoDensityMul > 1`), framed like [cargo].
  /// Without it the normal pod is drawn with steel straps.
  final ui.Image? cargoHeavy;

  /// The pod sprite for a level with this cargo density multiplier, or null
  /// for the shared one.
  ui.Image? cargoFor(double densityMul) =>
      densityMul > 1.0 ? (cargoHeavy ?? cargo) : cargo;

  static const empty = ThemeAssets();
  static const decorFrames = 4;

  bool get hasParallax => far != null || mid != null || near != null;

  static final Map<String, ThemeAssets> _cache = {};
  static Set<String>? _manifest;

  static Future<ThemeAssets> load(Images images, ThemeSpec theme) async {
    final cached = _cache[theme.id];
    if (cached != null) return cached;
    // Only request files that are bundled: Flame's image cache leaves an
    // unhandled error behind for a missing asset even when load() is caught.
    _manifest ??= (await AssetManifest.loadFromAssetBundle(rootBundle))
        .listAssets()
        .toSet();
    Future<ui.Image?> tryLoad(String file) async {
      final path = '${theme.assetDir}/$file';
      if (!_manifest!.contains('${images.prefix}$path')) return null;
      try {
        return await images.load(path);
      } catch (_) {
        return null;
      }
    }

    final assets = ThemeAssets(
      rock: await tryLoad('rock.png'),
      far: await tryLoad('far.png'),
      mid: await tryLoad('mid.png'),
      near: await tryLoad('near.png'),
      decor: await tryLoad('decor.png'),
      cargo: await tryLoad('cargo.png'),
      cargoHeavy: await tryLoad('cargo_heavy.png'),
    );
    _cache[theme.id] = assets;
    return assets;
  }
}
